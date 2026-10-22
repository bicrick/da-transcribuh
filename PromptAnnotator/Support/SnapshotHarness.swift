import AppKit

/// Launch with `-DTSnapshotDir <dir> -DTSnapshotTabs clipboard,configuration`
/// to render each listed Settings tab from the live window into PNGs:
/// `<tab>-top.png`, `<tab>-bottom.png` (window, scrolled), and
/// `<tab>-full.png` (the whole scroll document). Quits when done.
/// The app draws its own views, so no Screen Recording permission is needed.
@MainActor
enum SnapshotHarness {
    private static var started = false

    static func run(select: @escaping @MainActor (SettingsPage) -> Void) {
        guard let dir = UserDefaults.standard.string(forKey: "DTSnapshotDir"), !started else { return }
        started = true
        let pages = (UserDefaults.standard.string(forKey: "DTSnapshotTabs") ?? "clipboard")
            .split(separator: ",")
            .compactMap { SettingsPage(rawValue: String($0)) }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            for page in pages {
                select(page)
                try? await Task.sleep(nanoseconds: 1_200_000_000)
                guard let window = NSApp.windows.first(where: { $0.isVisible && $0.contentView.flatMap(pageScroll(in:)) != nil }),
                      let content = window.contentView,
                      let scroll = pageScroll(in: content),
                      let doc = scroll.documentView else { continue }
                scroll.contentView.scroll(to: .zero)
                scroll.reflectScrolledClipView(scroll.contentView)
                try? await Task.sleep(nanoseconds: 400_000_000)
                write(window.contentView?.superview ?? content, to: "\(dir)/\(page.rawValue)-top.png")
                let maxY = max(0, doc.frame.height - scroll.contentView.bounds.height)
                scroll.contentView.scroll(to: NSPoint(x: 0, y: doc.isFlipped ? maxY : 0))
                scroll.reflectScrolledClipView(scroll.contentView)
                try? await Task.sleep(nanoseconds: 600_000_000)
                write(window.contentView?.superview ?? content, to: "\(dir)/\(page.rawValue)-bottom.png")
                write(doc, to: "\(dir)/\(page.rawValue)-full.png")
            }
            FileHandle.standardError.write(Data("dtsnap done\n".utf8))
            NSApp.terminate(nil)
        }
    }

    /// The tallest scroll view with a document taller than zero is the page body.
    private static func pageScroll(in root: NSView) -> NSScrollView? {
        var best: NSScrollView?
        var stack = [root]
        while let view = stack.popLast() {
            if let s = view as? NSScrollView, let d = s.documentView, d.frame.height > 0,
               s.frame.height > (best?.frame.height ?? 0) {
                best = s
            }
            stack.append(contentsOf: view.subviews)
        }
        return best
    }

    private static func write(_ view: NSView, to path: String) {
        let bounds = view.bounds
        guard let rep = view.bitmapImageRepForCachingDisplay(in: bounds) else { return }
        view.cacheDisplay(in: bounds, to: rep)
        guard let data = rep.representation(using: .png, properties: [:]) else { return }
        try? data.write(to: URL(fileURLWithPath: path))
        FileHandle.standardError.write(Data("dtsnap \(path) \(Int(bounds.width))x\(Int(bounds.height))\n".utf8))
    }
}
