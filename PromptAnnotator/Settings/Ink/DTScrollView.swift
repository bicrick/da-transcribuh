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
    /// Lazy mode hosts the content in a native SwiftUI `ScrollView` (system
    /// scroller hidden) so a `LazyVStack` inside builds only the visible rows.
    /// The default AppKit host sizes an `NSHostingView` to the content's full
    /// fitting height, which builds every row of a lazy stack. The Ink rail,
    /// gutter and drag are the same in both modes.
    var lazy: Bool = false
    @ViewBuilder var content: () -> Content

    /// Scroller chrome lives in a reference model that only the rail observes.
    /// Root cause of slow tab switches and scroll jank: geometry / hover /
    /// flash were `@State` here, so every scroll tick or hover re-ran this
    /// body → `updateNSView` → replaced the hosted root view and forced a full
    /// synchronous content layout. `@State` holding a class does not observe it.
    @State private var chrome = DTScrollChrome()

    var body: some View {
        HStack(alignment: .top, spacing: showsIndicators ? Ink.scrollerGutterGap : 0) {
            Group {
                if lazy {
                    ScrollView(.vertical, showsIndicators: false) {
                        content()
                            .padding(.bottom, bottomInset)
                            .background(DTNativeScrollProbe(chrome: chrome))
                    }
                } else {
                    DTAppKitScrollHost(
                        bottomInset: bottomInset,
                        chrome: chrome
                    ) {
                        content()
                    }
                }
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
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        GeometryReader { geo in
            let trackH = max(geo.size.height, 1)
            // Whole points keep the 2pt checks on device pixels at 1x and 2x.
            let thumbH = geometry.thumbHeight(trackH: trackH, minH: Ink.scrollerThumbMin).rounded()
            let thumbY = geometry.thumbY(trackH: trackH, minH: Ink.scrollerThumbMin).rounded()

            ZStack(alignment: .top) {
                // Track: flat Paint gray with the ink border.
                Rectangle()
                    .fill(Ink.scrollerTrack)
                    .overlay(Rectangle().strokeBorder(Ink.label, lineWidth: Ink.stroke))
                    .allowsHitTesting(false)
                // Thumb: "missing texture" checkerboard, one cached tile, tiled by the GPU.
                Image(nsImage: DTCheckerTile.image(dark: scheme == .dark))
                    .resizable(resizingMode: .tile)
                    .interpolation(.none)
                    .frame(height: thumbH)
                    .overlay(Rectangle().strokeBorder(Ink.label, lineWidth: Ink.stroke))
                    .offset(y: thumbY)
                    .allowsHitTesting(false)
                DTScrollDragSurface(geometry: geometry, scrollView: scrollView, onDragging: onDragging)
            }
        }
        .frame(width: Ink.scrollerWidth)
        .frame(maxHeight: .infinity)
    }
}

/// 2x2 checker tile (each check `Ink.scrollerCheck` pt) built once per appearance.
/// Drawn with integer rects so it stays crisp at every backing scale.
enum DTCheckerTile {
    private static let light = make(a: Ink.scrollerCheckLightA, b: Ink.scrollerCheckLightB)
    private static let dark = make(a: Ink.scrollerCheckDarkA, b: Ink.scrollerCheckDarkB)

    static func image(dark isDark: Bool) -> NSImage { isDark ? dark : light }

    private static func make(a: NSColor, b: NSColor) -> NSImage {
        let c = Ink.scrollerCheck
        let image = NSImage(size: NSSize(width: c * 2, height: c * 2))
        // Explicit 1x and 2x bitmaps: no resampling, so checks land on whole pixels.
        for scale in [1, 2] {
            let px = Int(c) * 2 * scale
            guard let rep = NSBitmapImageRep(
                bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px,
                bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
            ) else { continue }
            rep.size = image.size
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
            a.setFill()
            NSRect(x: 0, y: 0, width: c * 2, height: c * 2).fill()
            b.setFill()
            NSRect(x: c, y: 0, width: c, height: c).fill()
            NSRect(x: 0, y: c, width: c, height: c).fill()
            NSGraphicsContext.restoreGraphicsState()
            image.addRepresentation(rep)
        }
        return image
    }
}

// MARK: - AppKit scroll host

/// Width the hosted page lays out at. Published by the scroll host from the
/// clip width.
@MainActor
final class DTHostedWidth: ObservableObject {
    @Published var value: CGFloat?

    /// Last clip width any host saw. A tab switch builds a fresh host, and
    /// seeding it here lets the first frame lay out at the right width
    /// instead of drawing one unwrapped frame.
    static var lastKnown: CGFloat?

    init() { value = Self.lastKnown }
}

/// Pins the hosted root to the clip width.
///
/// Root cause of pages drawing too high (Models 21pt, General and Perf 14pt
/// in the 1040x700 audit): `sizingOptions = [.intrinsicContentSize]` makes
/// the hosting view report SwiftUI's ideal size, and the ideal size is
/// measured at an unconstrained width. Text there does not wrap, so the
/// document came out shorter than the wrapped page. The hosting view then
/// centred the taller page in the short frame, which pushed the title up and
/// clipped the bottom by half the overflow each. Pinning the width makes the
/// ideal height the real height. Onboarding hit the same bug and fixed it
/// with a fixed page width. This fixes it once for every page.
private struct DTWidthPinnedRoot<Content: View>: View {
    @ObservedObject var width: DTHostedWidth
    var content: Content

    var body: some View {
        content.frame(width: width.value, alignment: .topLeading)
    }
}

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
        private let hostedWidth = DTHostedWidth()
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
            let root = rootView(parent.content(), bottomInset: parent.bottomInset)
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
            hosting?.rootView = rootView(content, bottomInset: bottomInset)
            hosting?.invalidateIntrinsicContentSize()
            guard let scroll = hosting?.enclosingScrollView else { return }
            scheduleRelayout(from: scroll)
        }

        private func rootView(_ content: Content, bottomInset: CGFloat) -> AnyView {
            // A nested hosting view starts a fresh environment; repeat the no-ring rule.
            AnyView(DTWidthPinnedRoot(width: hostedWidth, content: content.padding(.bottom, bottomInset).focusEffectDisabled()))
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
                    NotificationCenter.default.removeObserver(
                        self,
                        name: NSView.frameDidChangeNotification,
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
                // A new clip width rewraps the page, so the height must follow.
                clip.postsFrameChangedNotifications = true
                NotificationCenter.default.addObserver(
                    self,
                    selector: #selector(clipFrameChanged(_:)),
                    name: NSView.frameDidChangeNotification,
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

        @objc private func clipFrameChanged(_ note: Notification) {
            guard let clip = note.object as? NSClipView,
                  let scroll = clip.enclosingScrollView else { return }
            let width = clip.bounds.width
            guard width > 0, abs((hostedWidth.value ?? -1) - width) > 0.5 else { return }
            scheduleRelayout(from: scroll)
        }

        @objc private func documentFrameChanged(_ note: Notification) {
            guard let doc = note.object as? NSView,
                  let scroll = doc.enclosingScrollView else { return }
            publish(from: scroll)
        }

        private func relayoutAndPublish(from scroll: NSScrollView) {
            // One pass from the top covers document and hosting view too.
            scroll.layoutSubtreeIfNeeded()
            // Lay the page out at the clip width first. A new width re-renders
            // the hosted root, so measure on the next turn, not now.
            let clipWidth = scroll.contentView.bounds.width
            if clipWidth > 0, abs((hostedWidth.value ?? -1) - clipWidth) > 0.5 {
                hostedWidth.value = clipWidth
                DTHostedWidth.lastKnown = clipWidth
                hosting?.invalidateIntrinsicContentSize()
                scheduleRelayout(from: scroll)
                publish(from: scroll)
                return
            }
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
        // Lazy mode scrolls a SwiftUI-owned document. Handle an unflipped one too.
        let flipped = scroll.documentView?.isFlipped ?? true
        bounds.origin.y = flipped ? target : scrollable - target
        clip.setBoundsOrigin(bounds.origin)
        scroll.reflectScrolledClipView(clip)
    }
}


// MARK: - Lazy mode probe

/// Sits behind the content of a native SwiftUI `ScrollView` and feeds the Ink
/// rail from the backing `NSScrollView` (clip bounds for the offset, document
/// frame for the content height). macOS 14 has no `onScrollGeometryChange`.
private struct DTNativeScrollProbe: NSViewRepresentable {
    let chrome: DTScrollChrome

    func makeNSView(context: Context) -> ProbeView {
        let view = ProbeView()
        view.chrome = chrome
        return view
    }

    func updateNSView(_ view: ProbeView, context: Context) {
        view.chrome = chrome
        view.bind()
    }

    final class ProbeView: NSView {
        weak var chrome: DTScrollChrome?
        private weak var observed: NSScrollView?
        private var lastOffset: CGFloat = -1
        private var pending = false

        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            bind()
        }

        override func setFrameSize(_ newSize: NSSize) {
            super.setFrameSize(newSize)
            schedulePublish()
        }

        deinit { NotificationCenter.default.removeObserver(self) }

        func bind() {
            guard window != nil, let scroll = enclosingScrollView, scroll !== observed else { return }
            NotificationCenter.default.removeObserver(self)
            observed = scroll
            scroll.hasVerticalScroller = false
            scroll.hasHorizontalScroller = false
            let clip = scroll.contentView
            clip.postsBoundsChangedNotifications = true
            NotificationCenter.default.addObserver(
                self, selector: #selector(boundsChanged(_:)),
                name: NSView.boundsDidChangeNotification, object: clip
            )
            NotificationCenter.default.addObserver(
                self, selector: #selector(frameChanged(_:)),
                name: NSView.frameDidChangeNotification, object: clip
            )
            if let doc = scroll.documentView {
                doc.postsFrameChangedNotifications = true
                NotificationCenter.default.addObserver(
                    self, selector: #selector(frameChanged(_:)),
                    name: NSView.frameDidChangeNotification, object: doc
                )
            }
            chrome?.scrollView = scroll
            schedulePublish()
        }

        @objc private func boundsChanged(_ note: Notification) { publish(scrolled: true) }
        @objc private func frameChanged(_ note: Notification) { schedulePublish() }

        /// Frame changes land inside SwiftUI layout. Publishing there would
        /// mutate observed state during a view update, so hop once.
        private func schedulePublish() {
            guard !pending else { return }
            pending = true
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.pending = false
                self.publish(scrolled: false)
            }
        }

        private func publish(scrolled: Bool) {
            guard let scroll = observed, let chrome else { return }
            let clip = scroll.contentView
            let viewport = clip.bounds.height
            let content = max(scroll.documentView?.frame.height ?? 0, frame.height)
            let flipped = scroll.documentView?.isFlipped ?? true
            let originY = flipped ? clip.bounds.origin.y : content - viewport - clip.bounds.origin.y
            let geometry = DTScrollGeometry.fromFlippedClip(
                contentHeight: content, viewportHeight: viewport, originY: originY
            )
            if geometry != chrome.geometry { chrome.geometry = geometry }
            if chrome.scrollView !== scroll { chrome.scrollView = scroll }
            if scrolled, abs(originY - lastOffset) > 0.5 { chrome.flash() }
            lastOffset = originY
            DTNativeScrollProbeStats.updates += 1
            DTNativeScrollProbeStats.lastOffset = geometry.offset
            DTNativeScrollProbeStats.lastContent = content
        }
    }
}

/// Read by PerfSuite to confirm the rail follows a lazy scroll.
@MainActor
enum DTNativeScrollProbeStats {
    static var updates = 0
    static var lastOffset: CGFloat = 0
    static var lastContent: CGFloat = 0
}
