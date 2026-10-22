import AppKit

/// Launch with `-DTSnapshotPanel <dir>` to render the live clipboard panel and its
/// preview (cacheDisplay of the real windows, no screen recording needed):
/// `clip-panel-top.png`, `clip-preview.png`, `clip-panel-scrolled.png`. Then it quits.
@MainActor
enum PanelSnapshotHarness {
    static func run() {
        guard let dir = UserDefaults.standard.string(forKey: "DTSnapshotPanel") else { return }
        func log(_ s: String) { FileHandle.standardError.write(Data("dtsnap \(s)\n".utf8)) }
        func after(_ ms: Int, _ body: @escaping @MainActor () -> Void) {
            DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(ms)) { MainActor.assumeIsolated(body) }
        }
        after(2500) {
            ClipboardHistoryPanelController.shared.show()
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
                    log("done")
                    NSApp.terminate(nil)
                }
            }
        }
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
