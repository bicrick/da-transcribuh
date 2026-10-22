import AppKit
import SwiftUI

// MARK: - DTScrollView

/// ScrollView with native indicators hidden and a B/W track + square-ended thumb.
///
/// Thumb position is driven by the enclosing `NSClipView` bounds — not a SwiftUI
/// GeometryReader preference. AppKit scrolls by mutating clip-view bounds without a
/// SwiftUI layout pass, so preference-based offset stayed stuck at 0.
struct DTScrollView<Content: View>: View {
    var axes: Axis.Set = .vertical
    var showsIndicators: Bool = true
    /// Extra bottom inset so content clears a sticky footer (sidebar).
    var bottomInset: CGFloat = 0
    /// Trailing inset for the custom rail (sidebar uses a larger gutter so tiles stay clear).
    var railInset: CGFloat = Ink.scrollerInset
    @ViewBuilder var content: () -> Content

    @State private var offset: CGFloat = 0
    @State private var contentHeight: CGFloat = 0
    @State private var viewportHeight: CGFloat = 0
    @State private var hovering = false
    @State private var dragging = false
    @State private var visible = false
    @State private var fadeTask: Task<Void, Never>?

    var body: some View {
        GeometryReader { viewport in
            let vh = max(viewport.size.height, 1)
            ZStack(alignment: .trailing) {
                ScrollView(axes, showsIndicators: false) {
                    content()
                        .padding(.bottom, bottomInset)
                }
                .scrollIndicators(.hidden)
                .background(
                    DTScrollProbe { metrics in
                        let changed = abs(metrics.offset - offset) > 0.5
                            || abs(metrics.contentHeight - contentHeight) > 0.5
                            || abs(metrics.viewportHeight - viewportHeight) > 0.5
                        offset = metrics.offset
                        contentHeight = metrics.contentHeight
                        viewportHeight = metrics.viewportHeight
                        if changed { flash() }
                    }
                )
                .background(DTNativeScrollerHider())

                if showsIndicators && contentHeight > vh + 1 {
                    DTScrollerRail(
                        offset: offset,
                        contentHeight: contentHeight,
                        viewportHeight: max(viewportHeight, vh),
                        onDragging: { active in
                            dragging = active
                            if active { visible = true }
                            else { flash() }
                        }
                    )
                    .padding(.vertical, railInset)
                    .padding(.trailing, railInset)
                    .opacity((visible || hovering || dragging) ? 0.85 : 0)
                    .animation(.easeOut(duration: 0.18), value: visible || hovering || dragging)
                }
            }
            .onAppear {
                if viewportHeight < 1 { viewportHeight = vh }
            }
            .onChange(of: viewport.size.height) { _, height in
                if height > 1 { viewportHeight = height }
            }
        }
        .onHover { isHovering in
            hovering = isHovering
            if isHovering { flash() }
        }
    }

    private func flash() {
        visible = true
        fadeTask?.cancel()
        fadeTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 900_000_000)
            guard !Task.isCancelled, !hovering, !dragging else { return }
            withAnimation(.easeOut(duration: 0.25)) {
                visible = false
            }
        }
    }
}

// MARK: - Rail + thumb

private struct DTScrollerRail: View {
    var offset: CGFloat
    var contentHeight: CGFloat
    var viewportHeight: CGFloat
    var onDragging: (Bool) -> Void

    var body: some View {
        GeometryReader { geo in
            let trackH = max(geo.size.height, 1)
            let ratio = min(1, viewportHeight / max(contentHeight, 1))
            let thumbH = max(Ink.scrollerThumbMin, trackH * ratio)
            let scrollable = max(contentHeight - viewportHeight, 1)
            let travel = max(trackH - thumbH, 1)
            let thumbY = min(max(offset / scrollable, 0), 1) * travel

            ZStack(alignment: .top) {
                // Visuals do not steal hits — the drag surface owns the rail.
                RoundedRectangle(cornerRadius: Ink.scrollerRadius, style: .continuous)
                    .fill(Ink.window)
                    .overlay(
                        RoundedRectangle(cornerRadius: Ink.scrollerRadius, style: .continuous)
                            .strokeBorder(Ink.label, lineWidth: 1)
                    )
                    .overlay {
                        DTDitherGrip()
                            .opacity(0.3)
                            .clipShape(RoundedRectangle(cornerRadius: Ink.scrollerRadius, style: .continuous))
                    }
                    .allowsHitTesting(false)

                RoundedRectangle(cornerRadius: Ink.scrollerRadius, style: .continuous)
                    .fill(Ink.label)
                    .frame(height: thumbH)
                    .offset(y: thumbY)
                    .allowsHitTesting(false)

                DTScrollDragSurface(
                    contentHeight: contentHeight,
                    viewportHeight: viewportHeight,
                    onDragging: onDragging
                )
            }
        }
        .frame(width: Ink.scrollerWidth)
        .frame(maxHeight: .infinity)
    }
}

// MARK: - AppKit helpers

private struct DTScrollMetrics: Equatable {
    var offset: CGFloat
    var contentHeight: CGFloat
    var viewportHeight: CGFloat
}

/// Walks up to the enclosing `NSScrollView`, enables clip-view bounds notifications,
/// and reports scroll offset / content / viewport sizes whenever AppKit scrolls.
private struct DTScrollProbe: NSViewRepresentable {
    var onChange: (DTScrollMetrics) -> Void

    func makeNSView(context: Context) -> DTScrollProbeView {
        let view = DTScrollProbeView()
        view.onChange = onChange
        return view
    }

    func updateNSView(_ nsView: DTScrollProbeView, context: Context) {
        nsView.onChange = onChange
        nsView.attachIfNeeded()
        nsView.publish()
    }

    final class DTScrollProbeView: NSView {
        var onChange: ((DTScrollMetrics) -> Void)?
        private weak var observedClip: NSClipView?
        private weak var observedDoc: NSView?
        private var last: DTScrollMetrics?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            attachIfNeeded()
            publish()
        }

        override func viewDidMoveToSuperview() {
            super.viewDidMoveToSuperview()
            attachIfNeeded()
            publish()
        }

        func attachIfNeeded() {
            guard let scroll = enclosingScrollView() else { return }
            let clip = scroll.contentView
            if observedClip !== clip {
                detach()
                clip.postsBoundsChangedNotifications = true
                NotificationCenter.default.addObserver(
                    self,
                    selector: #selector(clipBoundsChanged(_:)),
                    name: NSView.boundsDidChangeNotification,
                    object: clip
                )
                observedClip = clip
            }
            if let doc = scroll.documentView, observedDoc !== doc {
                if let previous = observedDoc {
                    NotificationCenter.default.removeObserver(
                        self,
                        name: NSView.frameDidChangeNotification,
                        object: previous
                    )
                }
                doc.postsFrameChangedNotifications = true
                NotificationCenter.default.addObserver(
                    self,
                    selector: #selector(documentFrameChanged(_:)),
                    name: NSView.frameDidChangeNotification,
                    object: doc
                )
                observedDoc = doc
            }
        }

        deinit {
            NotificationCenter.default.removeObserver(self)
        }

        private func detach() {
            if let clip = observedClip {
                NotificationCenter.default.removeObserver(
                    self,
                    name: NSView.boundsDidChangeNotification,
                    object: clip
                )
            }
            observedClip = nil
        }

        @objc private func clipBoundsChanged(_ note: Notification) {
            publish()
        }

        @objc private func documentFrameChanged(_ note: Notification) {
            publish()
        }

        func publish() {
            guard let scroll = enclosingScrollView() else { return }
            let clip = scroll.contentView
            let doc = scroll.documentView
            let viewport = clip.bounds.height
            let content = max(doc?.frame.height ?? 0, viewport)
            // SwiftUI's hosted document is flipped: y=0 at top, increases as you scroll down.
            let originY = clip.bounds.origin.y
            let offset: CGFloat
            if clip.isFlipped || doc?.isFlipped == true {
                offset = max(0, originY)
            } else {
                // Unflipped: top of document is at high y.
                let scrollable = max(content - viewport, 0)
                offset = max(0, scrollable - originY)
            }
            let metrics = DTScrollMetrics(
                offset: offset,
                contentHeight: content,
                viewportHeight: viewport
            )
            guard metrics != last else { return }
            last = metrics
            // Avoid publishing into SwiftUI during an in-flight view update.
            DispatchQueue.main.async { [weak self] in
                self?.onChange?(metrics)
            }
        }

        private func enclosingScrollView() -> NSScrollView? {
            var current: NSView? = self
            while let node = current {
                if let scroll = node as? NSScrollView { return scroll }
                current = node.superview
            }
            return nil
        }
    }
}

/// Suppresses the stock NSScrollView scroller chrome under a SwiftUI ScrollView.
private struct DTNativeScrollerHider: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { Self.hide(from: view) }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async { Self.hide(from: nsView) }
    }

    static func hide(from view: NSView) {
        var current: NSView? = view
        while let node = current {
            if let scroll = node as? NSScrollView {
                scroll.hasVerticalScroller = false
                scroll.hasHorizontalScroller = false
                scroll.scrollerStyle = .overlay
                scroll.autohidesScrollers = true
                scroll.verticalScroller?.alphaValue = 0
                scroll.horizontalScroller?.alphaValue = 0
                scroll.verticalScroller?.isHidden = true
                scroll.horizontalScroller?.isHidden = true
                return
            }
            current = node.superview
        }
    }
}

/// Click / drag on the custom rail scrolls the enclosing NSScrollView.
private struct DTScrollDragSurface: NSViewRepresentable {
    var contentHeight: CGFloat
    var viewportHeight: CGFloat
    var onDragging: (Bool) -> Void

    func makeNSView(context: Context) -> DTScrollDragNSView {
        let view = DTScrollDragNSView()
        view.onDragging = onDragging
        return view
    }

    func updateNSView(_ nsView: DTScrollDragNSView, context: Context) {
        nsView.contentHeight = contentHeight
        nsView.viewportHeight = viewportHeight
        nsView.onDragging = onDragging
    }
}

private final class DTScrollDragNSView: NSView {
    var contentHeight: CGFloat = 0
    var viewportHeight: CGFloat = 0
    var onDragging: ((Bool) -> Void)?
    private var dragThumb = false
    private var grabOffsetInThumb: CGFloat = 0

    override var isFlipped: Bool { true }

    override func mouseDown(with event: NSEvent) {
        onDragging?(true)
        let local = convert(event.locationInWindow, from: nil)
        let metrics = thumbMetrics()
        if local.y >= metrics.thumbY, local.y <= metrics.thumbY + metrics.thumbH {
            dragThumb = true
            grabOffsetInThumb = local.y - metrics.thumbY
        } else {
            dragThumb = false
            jump(to: local.y, pinThumbCenter: true)
        }
    }

    override func mouseDragged(with event: NSEvent) {
        let local = convert(event.locationInWindow, from: nil)
        if dragThumb {
            let metrics = thumbMetrics()
            let thumbTop = local.y - grabOffsetInThumb
            jump(to: thumbTop + metrics.thumbH / 2, pinThumbCenter: true)
        } else {
            jump(to: local.y, pinThumbCenter: true)
        }
    }

    override func mouseUp(with event: NSEvent) {
        dragThumb = false
        onDragging?(false)
    }

    private struct ThumbMetrics {
        var trackH: CGFloat
        var thumbH: CGFloat
        var thumbY: CGFloat
        var scrollable: CGFloat
        var travel: CGFloat
    }

    private func thumbMetrics() -> ThumbMetrics {
        let trackH = max(bounds.height, 1)
        let ratio = min(1, viewportHeight / max(contentHeight, 1))
        let thumbH = max(Ink.scrollerThumbMin, trackH * ratio)
        let scrollable = max(contentHeight - viewportHeight, 1)
        let travel = max(trackH - thumbH, 1)
        let offset = currentOffset()
        let thumbY = min(max(offset / scrollable, 0), 1) * travel
        return ThumbMetrics(trackH: trackH, thumbH: thumbH, thumbY: thumbY, scrollable: scrollable, travel: travel)
    }

    private func currentOffset() -> CGFloat {
        guard let scroll = enclosingScrollView() else { return 0 }
        let clip = scroll.contentView
        let doc = scroll.documentView
        let viewport = clip.bounds.height
        let content = max(doc?.frame.height ?? 0, viewport)
        let originY = clip.bounds.origin.y
        if clip.isFlipped || doc?.isFlipped == true {
            return max(0, originY)
        }
        let scrollable = max(content - viewport, 0)
        return max(0, scrollable - originY)
    }

    private func jump(to trackY: CGFloat, pinThumbCenter: Bool) {
        guard let scroll = enclosingScrollView() else { return }
        let metrics = thumbMetrics()
        let yInTrack: CGFloat
        if pinThumbCenter {
            yInTrack = trackY - metrics.thumbH / 2
        } else {
            yInTrack = trackY
        }
        let fraction = min(max(yInTrack / max(metrics.travel, 1), 0), 1)
        let clip = scroll.contentView
        let doc = scroll.documentView
        let viewport = clip.bounds.height
        let content = max(doc?.frame.height ?? contentHeight, viewport)
        let scrollable = max(content - viewport, 0)
        let target = scrollable * fraction
        var bounds = clip.bounds
        if clip.isFlipped || doc?.isFlipped == true {
            bounds.origin.y = target
        } else {
            bounds.origin.y = scrollable - target
        }
        clip.setBoundsOrigin(bounds.origin)
        scroll.reflectScrolledClipView(clip)
    }

    private func enclosingScrollView() -> NSScrollView? {
        var current: NSView? = self
        while let node = current {
            if let scroll = node as? NSScrollView { return scroll }
            current = node.superview
        }
        return nil
    }
}
