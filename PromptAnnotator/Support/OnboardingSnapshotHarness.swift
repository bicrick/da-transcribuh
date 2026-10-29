import AppKit

/// Launch with `-DTOnboardingSnapshotDir <dir>` to open Welcome (even when setup
/// is finished), walk every step, and write `<n>-<step>.png` per step. Between
/// steps it samples the window over the transition and logs where the step title
/// ink starts (`dtonb ... ink=`). A step that swaps in place logs the same row
/// at every sample. Quits when done. No Screen Recording permission is needed.
@MainActor
enum OnboardingSnapshotHarness {
    private static var started = false

    static var isActive: Bool {
        UserDefaults.standard.string(forKey: "DTOnboardingSnapshotDir") != nil
    }

    static func run(go: @escaping @MainActor (OnboardingStep) -> Void) {
        guard let dir = UserDefaults.standard.string(forKey: "DTOnboardingSnapshotDir"), !started else { return }
        started = true
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            guard let window = OnboardingPresenter.shared.attachedWindow,
                  let content = window.contentView else {
                log("dtonb no window")
                NSApp.terminate(nil)
                return
            }
            log("dtonb window=\(Int(window.frame.width))x\(Int(window.frame.height)) content=\(Int(content.bounds.width))x\(Int(content.bounds.height)) min=\(window.contentMinSize)")
            // Forward through every step, then two steps back to cover retreat.
            var order = OnboardingStep.allCases
            order.append(.model)
            order.append(.language)
            order.append(.appearance)
            var seen = Set<OnboardingStep>()
            var previous: OnboardingStep = .welcome
            for step in order {
                go(step)
                var rows: [String] = []
                var elapsed = 0
                for mark in [0, 16, 33, 66, 100, 150, 220, 320, 500] {
                    if mark > elapsed {
                        try? await Task.sleep(nanoseconds: UInt64(mark - elapsed) * 1_000_000)
                        elapsed = mark
                    }
                    let probe = inkRows(in: content)
                    rows.append("\(mark):\(probe.divider)/\(probe.ink)")
                    if step == .permissions, previous == .welcome, mark == 100 {
                        write(content, to: "\(dir)/transition-mid.png")
                    }
                }
                log("dtonb \(previous.rawValue)->\(step.rawValue) \(rows.joined(separator: " "))")
                try? await Task.sleep(nanoseconds: 300_000_000)
                if let scroll = pageScroll(in: content), let doc = scroll.documentView {
                    let fits = doc.frame.height <= scroll.contentView.bounds.height + 0.5
                    log("dtonb fit \(step.rawValue) doc=\(Int(doc.frame.height)) viewport=\(Int(scroll.contentView.bounds.height)) originY=\(Int(scroll.contentView.bounds.origin.y)) insetTop=\(Int(scroll.contentInsets.top)) \(fits ? "FITS" : "SCROLLS") window=\(Int(window.frame.width))x\(Int(window.frame.height))")
                }
                if !seen.contains(step) {
                    seen.insert(step)
                    write(content, to: "\(dir)/\(step.rawValue + 1)-\(name(step)).png")
                }
                previous = step
            }
            log("dtonb done")
            NSApp.terminate(nil)
        }
    }

    private static func name(_ step: OnboardingStep) -> String {
        String(describing: step)
    }

    /// Rows in points, from the top of the content view. `divider` is the first full
    /// width rule under the rail. `ink` is the first row after it with page ink in
    /// the title column. Both should be the same at every sample of a transition.
    private static func inkRows(in view: NSView) -> (divider: Int, ink: Int) {
        let bounds = view.bounds
        guard let rep = view.bitmapImageRepForCachingDisplay(in: bounds) else { return (-1, -1) }
        view.cacheDisplay(in: bounds, to: rep)
        let scale = CGFloat(rep.pixelsHigh) / max(bounds.height, 1)
        let edgeX = Int(8 * scale)
        func differs(_ a: NSColor?, _ b: NSColor?, _ threshold: CGFloat) -> Bool {
            guard let a = a?.usingColorSpace(.sRGB), let b = b?.usingColorSpace(.sRGB) else { return false }
            return abs(a.redComponent - b.redComponent) > threshold
                || abs(a.greenComponent - b.greenComponent) > threshold
                || abs(a.blueComponent - b.blueComponent) > threshold
        }
        let start = Int(Ink.titleStripHeight * scale) + Int(4 * scale)
        let reference = rep.colorAt(x: edgeX, y: start)
        var divider = -1
        var y = start
        while y < rep.pixelsHigh / 2 {
            if differs(rep.colorAt(x: edgeX, y: y), reference, 0.05) { divider = y; break }
            y += 1
        }
        guard divider >= 0 else { return (-1, -1) }
        var ink = -1
        let x0 = Int(Ink.pageSide * scale)
        let x1 = min(rep.pixelsWide - 1, Int((Ink.pageSide + 260) * scale))
        y = divider + Int(3 * scale)
        rowLoop: while y < rep.pixelsHigh * 3 / 4 {
            let bg = rep.colorAt(x: edgeX, y: y)
            var x = x0
            while x < x1 {
                if differs(rep.colorAt(x: x, y: y), bg, 0.08) { ink = y; break rowLoop }
                x += 2
            }
            y += 1
        }
        return (Int(CGFloat(divider) / scale), ink < 0 ? -1 : Int(CGFloat(ink) / scale))
    }

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
        let target = view.superview ?? view
        let bounds = target.bounds
        guard let rep = target.bitmapImageRepForCachingDisplay(in: bounds) else { return }
        target.cacheDisplay(in: bounds, to: rep)
        guard let data = rep.representation(using: .png, properties: [:]) else { return }
        try? data.write(to: URL(fileURLWithPath: path))
        log("dtonb wrote \(path)")
    }

    private static func log(_ line: String) {
        FileHandle.standardError.write(Data((line + "\n").utf8))
    }
}
