import AppKit
import QuartzCore

/// Open / close motion for the clipboard list and its preview window.
///
/// Every move is an origin shift of a fixed-size window plus an alpha ramp,
/// so AppKit only moves the backing store. Nothing relayouts the SwiftUI content.
/// Callers order the window front and make it key before the animation starts,
/// so motion never delays keyboard focus.
@MainActor
enum PanelMotion {
    /// List panel open: fade + 6pt drop, ease-out.
    static let listOpen: TimeInterval = 0.17
    /// List panel close (Esc, outside click, toggle): fade + 4pt lift, ease-in.
    static let listClose: TimeInterval = 0.12
    static let listOpenDrop: CGFloat = 6
    static let listCloseLift: CGFloat = 4

    /// Preview slide out from the list edge.
    static let previewOpen: TimeInterval = 0.18
    /// Preview slide back toward the list.
    static let previewClose: TimeInterval = 0.13
    static let previewTravel: CGFloat = 12
    /// Content swap while the preview stays up (crossfade, no slide).
    static let previewSwap: TimeInterval = 0.08

    /// Ease-out (fast start, gentle settle). Close to CSS `ease-out`.
    static let easeOut = CAMediaTimingFunction(controlPoints: 0.16, 1, 0.3, 1)
    /// Ease-in for exits so the window leaves quickly.
    static let easeIn = CAMediaTimingFunction(controlPoints: 0.4, 0, 1, 1)

    /// System Reduce Motion. `-DTReduceMotion YES` forces it on for verification.
    static var reduceMotion: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
            || UserDefaults.standard.bool(forKey: "DTReduceMotion")
    }

    /// Animates `window` from `target` offset by `offset` (and alpha 0) to `target` at `alpha`.
    /// With Reduce Motion on there is no travel, only the fade.
    static func present(
        _ window: NSWindow,
        to target: NSRect,
        alpha: CGFloat,
        from offset: CGVector,
        duration: TimeInterval,
        fromCurrent: Bool = false
    ) {
        if !fromCurrent {
            let start = reduceMotion ? target : target.offsetBy(dx: offset.dx, dy: offset.dy)
            window.alphaValue = 0
            window.setFrame(start, display: false)
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = duration
            context.timingFunction = easeOut
            window.animator().alphaValue = alpha
            if window.frame != target {
                window.animator().setFrame(target, display: true)
            }
        }
    }

    /// Fades `window` out while moving it by `offset`, then runs `completion`.
    static func dismiss(
        _ window: NSWindow,
        toward offset: CGVector,
        duration: TimeInterval,
        completion: @escaping @MainActor () -> Void
    ) {
        let end = reduceMotion ? window.frame : window.frame.offsetBy(dx: offset.dx, dy: offset.dy)
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = duration
            context.timingFunction = easeIn
            window.animator().alphaValue = 0
            if end != window.frame {
                window.animator().setFrame(end, display: true)
            }
        }, completionHandler: {
            MainActor.assumeIsolated { completion() }
        })
    }
}

/// `-DTAnimSample YES` logs a window's origin and alpha every ~8ms for 300ms after
/// an animation starts (`dtanim <label> <ms> x y alpha`). Proof of timing without
/// screen recording. No effect without the argument.
@MainActor
enum AnimSampler {
    static var isEnabled: Bool { UserDefaults.standard.bool(forKey: "DTAnimSample") }

    /// One line, no timer (for in-place updates that must not move the window).
    static func mark(_ label: String, _ window: NSWindow) {
        guard isEnabled else { return }
        let f = window.frame
        let line = String(format: "dtanim %@ x=%.1f y=%.1f a=%.3f\n", label, f.origin.x, f.origin.y, window.alphaValue)
        FileHandle.standardError.write(Data(line.utf8))
    }

    static func sample(_ label: String, _ window: NSWindow) {
        guard isEnabled else { return }
        let start = CACurrentMediaTime()
        weak var target = window
        func log() {
            guard let target else { return }
            let ms = (CACurrentMediaTime() - start) * 1000
            let f = target.frame
            let line = String(format: "dtanim %@ %5.1f x=%.1f y=%.1f a=%.3f\n", label, ms, f.origin.x, f.origin.y, target.alphaValue)
            FileHandle.standardError.write(Data(line.utf8))
        }
        log()
        let timer = Timer(timeInterval: 0.008, repeats: true) { timer in
            MainActor.assumeIsolated {
                log()
                if CACurrentMediaTime() - start > 0.3 { timer.invalidate() }
            }
        }
        RunLoop.main.add(timer, forMode: .common)
    }
}
