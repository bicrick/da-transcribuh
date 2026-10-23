import AppKit

/// Launch with `-DTSnapshotPanel <dir>` to render the live clipboard panel and its
/// preview (cacheDisplay of the real windows, no screen recording needed):
/// `clip-panel-top.png`, `clip-preview.png`, `clip-panel-scrolled.png`,
/// `clip-panel-reopen.png`, `clip-panel-dark.png`, and `preview-<kind>-<light|dark>.png`.
/// Add `-DTSnapshotDemo YES` with a `-DTClipboardRoot` temp store to seed one item
/// of each kind (long text, images, mixed). Then it quits.
@MainActor
enum PanelSnapshotHarness {
    static func run() {
        guard let dir = UserDefaults.standard.string(forKey: "DTSnapshotPanel") else { return }
        func log(_ s: String) { FileHandle.standardError.write(Data("dtsnap \(s)\n".utf8)) }
        if UserDefaults.standard.bool(forKey: "DTSnapshotDemo") { seedDemoItems() }
        after(2500) {
            // Pin the light pass so the renders do not follow the system's auto dark mode.
            NSApp.appearance = NSAppearance(named: .aqua)
            ClipboardHistoryPanelController.shared.show()
            // Placement facts for marking the pointer on the render (AppKit points, y up).
            let mouse = NSEvent.mouseLocation
            let frame = ClipboardHistoryPanelController.shared.listFrame
            let vis = ScreenGeometry.screen(containingAppKitPoint: mouse)?.visibleFrame ?? .zero
            log("placement mouse=\(mouse.x),\(mouse.y) frame=\(frame.minX),\(frame.minY),\(frame.width),\(frame.height) visible=\(vis.minX),\(vis.minY),\(vis.width),\(vis.height) inside=\(frame.contains(mouse))")
            logOpenState("open", log)
            let wait = max(0, AppSettings.shared.clipboardPreviewDelayMs) + 700
            after(wait) {
                write(ClipboardHistoryPanelController.shared.window, "\(dir)/clip-panel-top.png", log)
                write(ClipboardPreviewPanelController.shared.window, "\(dir)/clip-preview.png", log)
                if let scroll = firstScrollView(in: ClipboardHistoryPanelController.shared.window?.contentView),
                   let doc = scroll.documentView {
                    let clip = scroll.contentView
                    let maxY = max(doc.frame.height - clip.bounds.height, 0)
                    clip.setBoundsOrigin(NSPoint(x: 0, y: (maxY / 2).rounded()))
                    scroll.reflectScrolledClipView(clip)
                    log("scrolled to \(Int(maxY / 2)) of \(Int(maxY))")
                }
                after(400) {
                    write(ClipboardHistoryPanelController.shared.window, "\(dir)/clip-panel-scrolled.png", log)
                    // Reopen: must land at the top with the search field focused.
                    ClipboardHistoryPanelController.shared.hide(animated: false)
                    ClipboardHistoryPanelController.shared.show()
                    after(max(0, AppSettings.shared.clipboardPreviewDelayMs) + 700) {
                        logOpenState("reopen", log)
                        write(ClipboardHistoryPanelController.shared.window, "\(dir)/clip-panel-reopen.png", log)
                        renderPreviews(dir: dir, suffix: "light", log: log) {
                            NSApp.appearance = NSAppearance(named: .darkAqua)
                            ClipboardHistoryPanelController.shared.hide(animated: false)
                            ClipboardHistoryPanelController.shared.show()
                            after(max(0, AppSettings.shared.clipboardPreviewDelayMs) + 700) {
                                write(ClipboardHistoryPanelController.shared.window, "\(dir)/clip-panel-dark.png", log)
                                renderPreviews(dir: dir, suffix: "dark", log: log) {
                                    log("done")
                                    NSApp.terminate(nil)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private static func after(_ ms: Int, _ body: @escaping @MainActor () -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(ms)) { MainActor.assumeIsolated(body) }
    }

    /// Scroll offset from the top and whether the search field holds focus.
    private static func logOpenState(_ label: String, _ log: (String) -> Void) {
        guard let window = ClipboardHistoryPanelController.shared.window else { return }
        var fromTop = -1
        if let scroll = firstScrollView(in: window.contentView), let doc = scroll.documentView {
            let clip = scroll.contentView
            let maxY = max(doc.frame.height - clip.bounds.height, 0)
            fromTop = Int(doc.isFlipped ? clip.bounds.origin.y : maxY - clip.bounds.origin.y)
        }
        let field = ClipboardHistoryPanelController.firstEditableTextField(in: window.contentView)
        let editor = window.firstResponder as? NSTextView
        let searchFocused = field != nil && editor?.delegate === field
        let mouse = NSEvent.mouseLocation
        let inside = ClipboardHistoryPanelController.shared.listFrame.contains(mouse)
        log("\(label) scrollFromTop=\(fromTop) searchFocused=\(searchFocused) key=\(window.isKeyWindow) mouse=\(Int(mouse.x)),\(Int(mouse.y)) mouseInside=\(inside)")
    }

    /// One preview per demo kind, rendered from the real preview window.
    private static func renderPreviews(dir: String, suffix: String, log: @escaping (String) -> Void,
                                       then done: @escaping @MainActor () -> Void) {
        let store = ClipboardHistoryStore.shared
        let wanted: [(String, (ClipboardItem) -> Bool)] = [
            ("mixed", { $0.isMixed }),
            ("image", { $0.kind == .image }),
            ("image-tall", { $0.kind == .image && ($0.imageHeight ?? 0) > ($0.imageWidth ?? 0) }),
            ("text-long", { $0.kind == .text && !$0.isMixed && ($0.text?.count ?? 0) > 1500 }),
        ]
        var queue = wanted.compactMap { name, match in store.items.first(where: match).map { (name, $0) } }
        func next() {
            guard !queue.isEmpty else { done(); return }
            let (name, item) = queue.removeFirst()
            ClipboardPreviewPanelController.shared.show(
                item: item,
                image: store.image(for: item),
                beside: ClipboardHistoryPanelController.shared.listFrame
            )
            after(450) {
                write(ClipboardPreviewPanelController.shared.window, "\(dir)/preview-\(name)-\(suffix).png", log)
                next()
            }
        }
        next()
    }

    /// Harness only, into the `-DTClipboardRoot` temp store: a long text, two
    /// images, and a mixed text + image copy on top.
    private static func seedDemoItems() {
        let store = ClipboardHistoryStore.shared
        store.historyLimitOverride = max(store.historyLimit, store.items.count + 8)
        let long = (1...60).map { "Line \($0): the preview must keep its border on all four sides." }
            .joined(separator: "\n")
        store.ingest(payload: .text(long), source: .pasteboard, applicationName: "Notes")
        store.ingest(payload: .image(png: PerfSuite.syntheticPNG(width: 900, height: 1600, seed: 7)),
                     source: .pasteboard, applicationName: "Preview")
        store.ingest(payload: .image(png: PerfSuite.syntheticPNG(width: 1600, height: 900, seed: 11)),
                     source: .pasteboard, applicationName: "Screenshot")
        store.ingest(
            payload: .mixed(
                text: "Quarterly roadmap\nShip clipboard previews with image and text from one copy.",
                png: PerfSuite.syntheticPNG(width: 1200, height: 700, seed: 3)
            ),
            source: .pasteboard,
            applicationName: "Safari"
        )
    }

    private static func firstScrollView(in view: NSView?) -> NSScrollView? {
        guard let view else { return nil }
        if let scroll = view as? NSScrollView { return scroll }
        for sub in view.subviews {
            if let hit = firstScrollView(in: sub) { return hit }
        }
        return nil
    }

    private static func write(_ window: NSWindow?, _ path: String, _ log: (String) -> Void) {
        guard let view = window?.contentView, window?.isVisible == true else { log("no window for \(path)"); return }
        guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
        log("wrote \(path) \(rep.pixelsWide)x\(rep.pixelsHigh)")
    }
}
