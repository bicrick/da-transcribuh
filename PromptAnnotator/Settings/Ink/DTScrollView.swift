import AppKit
import SwiftUI

// MARK: - DTScrollView

/// Scroll view with a reserved trailing gutter and a Paint ink scroller.
///
/// Metrics come from the hosted `NSScrollView` after layout (`boundsDidChange` /
/// document `frameDidChange`). GeometryReader preferences stay at 0 under
/// AppKit-driven scrolls — do not bring them back.
///
/// Root cause of a static thumb: `NSHostingView` without
/// `sizingOptions = [.intrinsicContentSize]` collapses the document to the
/// clip height, so `contentHeight == viewportHeight` and travel is zero.
struct DTScrollView<Content: View>: View {
    var axes: Axis.Set = .vertical
    var showsIndicators: Bool = true
    var bottomInset: CGFloat = 0
    @ViewBuilder var content: () -> Content

    /// Scroller chrome lives in a reference model that only the rail observes.
    /// Root cause of slow tab switches and scroll jank: geometry / hover /
    /// flash were `@State` here, so every scroll tick or hover re-ran this
    /// body → `updateNSView` → replaced the hosted root view and forced a full
    /// synchronous content layout. `@State` holding a class does not observe it.
    @State private var chrome = DTScrollChrome()

    var body: some View {
        HStack(alignment: .top, spacing: showsIndicators ? Ink.scrollerGutterGap : 0) {
            DTAppKitScrollHost(
                bottomInset: bottomInset,
                chrome: chrome
            ) {
                content()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            if showsIndicators {
                DTScrollerColumn(chrome: chrome)
            }
        }
        .onHover { isHovering in
            chrome.setHovering(isHovering)
        }
    }
}

/// Scroll geometry + scroller visibility. Mutations re-render the rail only.
@MainActor
final class DTScrollChrome: ObservableObject {
    @Published var geometry = DTScrollGeometry(contentHeight: 0, viewportHeight: 0, offset: 0)
    @Published var visible = false
    @Published private(set) var hovering = false
    @Published private(set) var dragging = false
    weak var scrollView: NSScrollView?
    private var fadeTask: Task<Void, Never>?

    var emphasized: Bool { visible || hovering || dragging }

    func setHovering(_ value: Bool) {
        if hovering != value { hovering = value }
        if value { flash() }
    }

    func setDragging(_ active: Bool) {
        if dragging != active { dragging = active }
        if active {
            if !visible { visible = true }
        } else {
            flash()
        }
    }

    func flash() {
        if !visible { visible = true }
        fadeTask?.cancel()
        fadeTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 900_000_000)
            guard let self, !Task.isCancelled, !self.hovering, !self.dragging else { return }
            withAnimation(.easeOut(duration: 0.25)) {
                self.visible = false
            }
        }
    }
}

private struct DTScrollerColumn: View {
    @ObservedObject var chrome: DTScrollChrome

    var body: some View {
        ZStack {
            Color.clear
            if chrome.geometry.needsScroller {
                // Track is full height of the scroll area (flush with
                // container top/bottom). Do not pad — scrollerInset gaps
                // were the root cause of short tracks after #24.
                DTScrollerRail(
                    geometry: chrome.geometry,
                    scrollView: chrome.scrollView,
                    onDragging: { [weak chrome] active in chrome?.setDragging(active) }
                )
                .opacity(chrome.emphasized ? 1 : 0.55)
                .animation(.easeOut(duration: 0.18), value: chrome.emphasized)
            }
        }
        .frame(width: Ink.scrollerWidth)
        .frame(maxHeight: .infinity)
    }
}

// MARK: - Rail

private struct DTScrollerRail: View {
    var geometry: DTScrollGeometry
    var scrollView: NSScrollView?
    var onDragging: (Bool) -> Void

    var body: some View {
        GeometryReader { geo in
            let trackH = max(geo.size.height, 1)
            let thumbH = geometry.thumbHeight(trackH: trackH, minH: Ink.scrollerThumbMin)
            let thumbY = geometry.thumbY(trackH: trackH, minH: Ink.scrollerThumbMin)

            ZStack(alignment: .top) {
                Rectangle()
                    .fill(Ink.window)
                    .overlay(Rectangle().strokeBorder(Ink.label, lineWidth: Ink.stroke))
                    .overlay {
                        DTDitherGrip()
                            .opacity(0.28)
                            .clipShape(Rectangle())
                    }
                    .allowsHitTesting(false)

                Rectangle()
                    .fill(Ink.label)
                    .overlay(Rectangle().strokeBorder(Ink.label, lineWidth: Ink.stroke))
                    .frame(height: thumbH)
                    .offset(y: thumbY)
                    .allowsHitTesting(false)

                DTScrollDragSurface(
                    geometry: geometry,
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
    var chrome: DTScrollChrome
    @ViewBuilder var content: () -> Content

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> DTScrollHostView {
        let host = DTScrollHostView()
        context.coordinator.inViewUpdate = true
        context.coordinator.install(in: host)
        context.coordinator.inViewUpdate = false
        // Synchronous — drag surface must see the scroll view on first paint.
        chrome.scrollView = host.scrollView
        return host
    }

    func updateNSView(_ nsView: DTScrollHostView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.inViewUpdate = true
        context.coordinator.updateContent(content(), bottomInset: bottomInset)
        context.coordinator.inViewUpdate = false
        if chrome.scrollView !== nsView.scrollView {
            chrome.scrollView = nsView.scrollView
        }
    }

    @MainActor
    final class Coordinator: NSObject {
        var parent: DTAppKitScrollHost
        /// True inside make/updateNSView — publishing then would mutate
        /// observed state during a SwiftUI view update.
        var inViewUpdate = false
        private var hosting: NSHostingView<AnyView>?
        private weak var document: DTFlippedDocumentView?
        private weak var observedClip: NSClipView?
        private weak var observedDoc: NSView?
        private var lastGeometry: DTScrollGeometry?

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
            // Without this, the document collapses to the clip height and the
            // thumb never travels (contentHeight == viewportHeight).
            hosting.sizingOptions = [.intrinsicContentSize]
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
            self.document = document
            host.scrollView.documentView = document

            let clip = host.scrollView.contentView
            NSLayoutConstraint.activate([
                document.widthAnchor.constraint(equalTo: clip.widthAnchor),
            ])
            attach(to: host.scrollView)
            // Not laid out here: the host has no window and no width yet, so
            // a synchronous pass measured the whole page at the wrong width
            // and then again once it landed (do it later, not twice).
            scheduleRelayout(from: host.scrollView)
        }

        func updateContent(_ content: Content, bottomInset: CGFloat) {
            hosting?.rootView = AnyView(content.padding(.bottom, bottomInset))
            hosting?.invalidateIntrinsicContentSize()
            guard let scroll = hosting?.enclosingScrollView else { return }
            scheduleRelayout(from: scroll)
        }

        private var relayoutScheduled = false

        /// Coalesces relayouts to one per main-queue turn. A tab switch calls
        /// updateNSView several times in a row and each one used to force a
        /// full synchronous SwiftUI layout of the page.
        private func scheduleRelayout(from scroll: NSScrollView) {
            guard !relayoutScheduled else { return }
            relayoutScheduled = true
            DispatchQueue.main.async { [weak self, weak scroll] in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.relayoutScheduled = false
                    // A page torn down by a tab switch still gets one last
                    // updateNSView. Measuring it off-window was wasted work
                    // billed to the next tab.
                    guard let scroll, scroll.window != nil else { return }
                    self.relayoutAndPublish(from: scroll)
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

        private func relayoutAndPublish(from scroll: NSScrollView) {
            // One pass from the top covers document and hosting view too.
            scroll.layoutSubtreeIfNeeded()
            // Apply intrinsic height so frame matches content (AL can still
            // leave the document at clip height without an explicit size).
            if let hosting, let document {
                let fitting = hosting.fittingSize
                let width = scroll.contentView.bounds.width
                let height = max(fitting.height, hosting.intrinsicContentSize.height)
                if height > 0, width > 0 {
                    var frame = document.frame
                    frame.size = CGSize(width: width, height: height)
                    if abs(frame.height - document.frame.height) > 0.5
                        || abs(frame.width - document.frame.width) > 0.5 {
                        document.frame = frame
                    }
                }
            }
            publish(from: scroll)
        }

        func publish(from scroll: NSScrollView) {
            let next = Self.readGeometry(from: scroll)
            guard next != lastGeometry else { return }
            let scrolled = abs(next.offset - (lastGeometry?.offset ?? -1)) > 0.5
            lastGeometry = next
            let chrome = parent.chrome
            let apply = {
                chrome.geometry = next
                if scrolled { chrome.flash() }
            }
            if inViewUpdate || !Thread.isMainThread {
                DispatchQueue.main.async(execute: apply)
            } else {
                apply()
            }
        }

        static func readGeometry(from scroll: NSScrollView) -> DTScrollGeometry {
            let clip = scroll.contentView
            let doc = scroll.documentView
            let viewport = clip.bounds.height
            // Do not max with viewport — that hid the collapsed-document bug.
            let content = doc?.frame.height ?? 0
            return DTScrollGeometry.fromFlippedClip(
                contentHeight: content,
                viewportHeight: viewport,
                originY: clip.bounds.origin.y
            )
        }
    }
}

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

// MARK: - Drag

private struct DTScrollDragSurface: NSViewRepresentable {
    var geometry: DTScrollGeometry
    var scrollView: NSScrollView?
    var onDragging: (Bool) -> Void

    func makeNSView(context: Context) -> DTScrollDragNSView {
        let view = DTScrollDragNSView()
        view.onDragging = onDragging
        view.boundScrollView = scrollView
        view.geometry = geometry
        return view
    }

    func updateNSView(_ nsView: DTScrollDragNSView, context: Context) {
        nsView.geometry = geometry
        nsView.boundScrollView = scrollView
        nsView.onDragging = onDragging
    }
}

private final class DTScrollDragNSView: NSView {
    var geometry = DTScrollGeometry(contentHeight: 0, viewportHeight: 0, offset: 0)
    weak var boundScrollView: NSScrollView?
    var onDragging: ((Bool) -> Void)?
    private var dragThumb = false
    private var grabOffsetInThumb: CGFloat = 0

    override var isFlipped: Bool { true }

    override func mouseDown(with event: NSEvent) {
        onDragging?(true)
        let local = convert(event.locationInWindow, from: nil)
        let trackH = max(bounds.height, 1)
        let thumbH = geometry.thumbHeight(trackH: trackH, minH: Ink.scrollerThumbMin)
        let thumbY = geometry.thumbY(trackH: trackH, minH: Ink.scrollerThumbMin)
        if local.y >= thumbY, local.y <= thumbY + thumbH {
            dragThumb = true
            grabOffsetInThumb = local.y - thumbY
        } else {
            dragThumb = false
            jump(to: local.y, trackH: trackH, thumbH: thumbH)
        }
    }

    override func mouseDragged(with event: NSEvent) {
        let local = convert(event.locationInWindow, from: nil)
        let trackH = max(bounds.height, 1)
        let thumbH = geometry.thumbHeight(trackH: trackH, minH: Ink.scrollerThumbMin)
        if dragThumb {
            jump(to: local.y - grabOffsetInThumb + thumbH / 2, trackH: trackH, thumbH: thumbH)
        } else {
            jump(to: local.y, trackH: trackH, thumbH: thumbH)
        }
    }

    override func mouseUp(with event: NSEvent) {
        dragThumb = false
        onDragging?(false)
    }

    private func jump(to trackY: CGFloat, trackH: CGFloat, thumbH: CGFloat) {
        guard let scroll = boundScrollView else { return }
        let travel = max(trackH - thumbH, 1)
        let yInTrack = trackY - thumbH / 2
        let fraction = min(max(yInTrack / travel, 0), 1)
        let clip = scroll.contentView
        let scrollable = geometry.scrollable
        let target = scrollable * fraction
        var bounds = clip.bounds
        bounds.origin.y = target
        clip.setBoundsOrigin(bounds.origin)
        scroll.reflectScrolledClipView(clip)
    }
}

