import AppKit
import SwiftUI

// MARK: - DTScrollView

/// Scroll view with a **reserved trailing gutter** for a Paint ink scroller.
///
/// Content never draws under the thumb: width shrinks by `Ink.scrollerGutter`.
/// Offset / sizes come from the hosting `NSScrollView` clip-view
/// (`boundsDidChange`), not a GeometryReader preference (those stay stuck at 0
/// under AppKit-driven scrolls and trackpad momentum).
struct DTScrollView<Content: View>: View {
    var axes: Axis.Set = .vertical
    var showsIndicators: Bool = true
    /// Extra bottom inset so content clears a sticky footer (sidebar).
    var bottomInset: CGFloat = 0
    @ViewBuilder var content: () -> Content

    @State private var offset: CGFloat = 0
    @State private var contentHeight: CGFloat = 0
    @State private var viewportHeight: CGFloat = 0
    @State private var hovering = false
    @State private var dragging = false
    @State private var visible = false
    @State private var fadeTask: Task<Void, Never>?
    @State private var scrollView: NSScrollView?

    private var needsScroller: Bool {
        showsIndicators && contentHeight > viewportHeight + 1
    }

    var body: some View {
        // Content | gap | track — content width never includes the gutter.
        HStack(alignment: .top, spacing: showsIndicators ? Ink.scrollerGutterGap : 0) {
            DTAppKitScrollHost(
                bottomInset: bottomInset,
                offset: $offset,
                contentHeight: $contentHeight,
                viewportHeight: $viewportHeight,
                scrollView: $scrollView,
                onScroll: { flash() }
            ) {
                content()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            // Keep the gutter even when content fits so headers/columns don't jump.
            if showsIndicators {
                ZStack {
                    Color.clear
                    if needsScroller {
                        DTScrollerRail(
                            offset: offset,
                            contentHeight: contentHeight,
                            viewportHeight: max(viewportHeight, 1),
                            scrollView: scrollView,
                            onDragging: { active in
                                dragging = active
                                if active { visible = true }
                                else { flash() }
                            }
                        )
                        .padding(.vertical, Ink.scrollerInset)
                        .opacity((visible || hovering || dragging) ? 1 : 0.55)
                        .animation(.easeOut(duration: 0.18), value: visible || hovering || dragging)
                    }
                }
                .frame(width: Ink.scrollerWidth)
                .frame(maxHeight: .infinity)
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

// MARK: - Rail + thumb (square, 2pt stroke)

private struct DTScrollerRail: View {
    var offset: CGFloat
    var contentHeight: CGFloat
    var viewportHeight: CGFloat
    var scrollView: NSScrollView?
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
                Rectangle()
                    .fill(Ink.window)
                    .overlay(
                        Rectangle()
                            .strokeBorder(Ink.label, lineWidth: Ink.stroke)
                    )
                    .overlay {
                        DTDitherGrip()
                            .opacity(0.28)
                            .clipShape(Rectangle())
                    }
                    .allowsHitTesting(false)

                Rectangle()
                    .fill(Ink.label)
                    .overlay(
                        Rectangle()
                            .strokeBorder(Ink.label, lineWidth: Ink.stroke)
                    )
                    .frame(height: thumbH)
                    .offset(y: thumbY)
                    .allowsHitTesting(false)

                DTScrollDragSurface(
                    contentHeight: contentHeight,
                    viewportHeight: viewportHeight,
                    scrollView: scrollView,
                    onDragging: onDragging
                )
            }
        }
        .frame(width: Ink.scrollerWidth)
        .frame(maxHeight: .infinity)
    }
}

// MARK: - AppKit scroll host

private struct DTAppKitScrollHost<Content: View>: NSViewRepresentable {
    var bottomInset: CGFloat
    @Binding var offset: CGFloat
    @Binding var contentHeight: CGFloat
    @Binding var viewportHeight: CGFloat
    @Binding var scrollView: NSScrollView?
    var onScroll: () -> Void
    @ViewBuilder var content: () -> Content

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> DTScrollHostView {
        let host = DTScrollHostView()
        context.coordinator.install(in: host)
        DispatchQueue.main.async {
            scrollView = host.scrollView
        }
        return host
    }

    func updateNSView(_ nsView: DTScrollHostView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.updateContent(content(), bottomInset: bottomInset)
        DispatchQueue.main.async {
            if scrollView !== nsView.scrollView {
                scrollView = nsView.scrollView
            }
        }
    }

    final class Coordinator: NSObject {
        var parent: DTAppKitScrollHost
        private var hosting: NSHostingView<AnyView>?
        private weak var observedClip: NSClipView?
        private weak var observedDoc: NSView?
        private var lastMetrics: DTScrollMetrics?

        init(parent: DTAppKitScrollHost) {
            self.parent = parent
            super.init()
        }

        deinit {
            NotificationCenter.default.removeObserver(self)
        }

        func install(in host: DTScrollHostView) {
            let root = AnyView(parent.content().padding(.bottom, parent.bottomInset))
            let hosting = NSHostingView(rootView: root)
            hosting.translatesAutoresizingMaskIntoConstraints = false
            self.hosting = hosting

            let document = DTFlippedDocumentView()
            document.translatesAutoresizingMaskIntoConstraints = false
            document.addSubview(hosting)
            NSLayoutConstraint.activate([
                hosting.leadingAnchor.constraint(equalTo: document.leadingAnchor),
                hosting.trailingAnchor.constraint(equalTo: document.trailingAnchor),
                hosting.topAnchor.constraint(equalTo: document.topAnchor),
                hosting.bottomAnchor.constraint(equalTo: document.bottomAnchor),
            ])
            host.scrollView.documentView = document

            let clip = host.scrollView.contentView
            NSLayoutConstraint.activate([
                document.widthAnchor.constraint(equalTo: clip.widthAnchor),
            ])
            attach(to: host.scrollView)
            publish(from: host.scrollView)
        }

        func updateContent(_ content: Content, bottomInset: CGFloat) {
            hosting?.rootView = AnyView(content.padding(.bottom, bottomInset))
            hosting?.invalidateIntrinsicContentSize()
            if let scroll = hosting?.enclosingScrollView {
                DispatchQueue.main.async { [weak self] in
                    self?.publish(from: scroll)
                }
            }
        }

        func attach(to scroll: NSScrollView) {
            let clip = scroll.contentView
            if observedClip !== clip {
                if let previous = observedClip {
                    NotificationCenter.default.removeObserver(
                        self,
                        name: NSView.boundsDidChangeNotification,
                        object: previous
                    )
                }
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

        @objc private func clipBoundsChanged(_ note: Notification) {
            guard let clip = note.object as? NSClipView,
                  let scroll = clip.enclosingScrollView else { return }
            publish(from: scroll)
        }

        @objc private func documentFrameChanged(_ note: Notification) {
            guard let doc = note.object as? NSView,
                  let scroll = doc.enclosingScrollView else { return }
            publish(from: scroll)
        }

        func publish(from scroll: NSScrollView) {
            let metrics = DTScrollMetrics.metrics(from: scroll)
            guard metrics != lastMetrics else { return }
            lastMetrics = metrics
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                let scrolled = abs(metrics.offset - self.parent.offset) > 0.5
                self.parent.offset = metrics.offset
                self.parent.contentHeight = metrics.contentHeight
                self.parent.viewportHeight = metrics.viewportHeight
                if scrolled {
                    self.parent.onScroll()
                }
            }
        }
    }
}

/// Flipped document so y=0 is the top — matches SwiftUI scroll direction.
private final class DTFlippedDocumentView: NSView {
    override var isFlipped: Bool { true }
}

private final class DTScrollHostView: NSView {
    let scrollView = NSScrollView()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        scrollView.drawsBackground = false
        scrollView.backgroundColor = .clear
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.scrollerStyle = .overlay
        scrollView.borderType = .noBorder
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.contentView.postsBoundsChangedNotifications = true
        addSubview(scrollView)
        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}

// MARK: - Metrics

private struct DTScrollMetrics: Equatable {
    var offset: CGFloat
    var contentHeight: CGFloat
    var viewportHeight: CGFloat

    static func metrics(from scroll: NSScrollView) -> DTScrollMetrics {
        let clip = scroll.contentView
        let doc = scroll.documentView
        let viewport = clip.bounds.height
        let content = max(doc?.frame.height ?? 0, viewport)
        let originY = clip.bounds.origin.y
        let offset: CGFloat
        if clip.isFlipped || doc?.isFlipped == true {
            offset = max(0, originY)
        } else {
            let scrollable = max(content - viewport, 0)
            offset = max(0, scrollable - originY)
        }
        return DTScrollMetrics(
            offset: offset,
            contentHeight: content,
            viewportHeight: viewport
        )
    }
}

// MARK: - Drag / click track

private struct DTScrollDragSurface: NSViewRepresentable {
    var contentHeight: CGFloat
    var viewportHeight: CGFloat
    var scrollView: NSScrollView?
    var onDragging: (Bool) -> Void

    func makeNSView(context: Context) -> DTScrollDragNSView {
        let view = DTScrollDragNSView()
        view.onDragging = onDragging
        return view
    }

    func updateNSView(_ nsView: DTScrollDragNSView, context: Context) {
        nsView.contentHeight = contentHeight
        nsView.viewportHeight = viewportHeight
        nsView.boundScrollView = scrollView
        nsView.onDragging = onDragging
    }
}

private final class DTScrollDragNSView: NSView {
    var contentHeight: CGFloat = 0
    var viewportHeight: CGFloat = 0
    weak var boundScrollView: NSScrollView?
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
            jump(to: local.y)
        }
    }

    override func mouseDragged(with event: NSEvent) {
        let local = convert(event.locationInWindow, from: nil)
        if dragThumb {
            let metrics = thumbMetrics()
            let thumbTop = local.y - grabOffsetInThumb
            jump(to: thumbTop + metrics.thumbH / 2)
        } else {
            jump(to: local.y)
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
        return ThumbMetrics(
            trackH: trackH,
            thumbH: thumbH,
            thumbY: thumbY,
            scrollable: scrollable,
            travel: travel
        )
    }

    private func resolvedScrollView() -> NSScrollView? {
        boundScrollView ?? enclosingScrollView()
    }

    private func currentOffset() -> CGFloat {
        guard let scroll = resolvedScrollView() else { return 0 }
        return DTScrollMetrics.metrics(from: scroll).offset
    }

    private func jump(to trackY: CGFloat) {
        guard let scroll = resolvedScrollView() else { return }
        let metrics = thumbMetrics()
        let yInTrack = trackY - metrics.thumbH / 2
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
