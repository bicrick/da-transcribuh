import AppKit
import CoreGraphics
import QuartzCore

/// Holds the synthetic ⌘V until the stop chord's modifiers are physically up.
///
/// A still-held ⌥, ⌃ or ⌘ can merge into the posted keystroke in apps that read live
/// modifier state (⌥⌘V is "Move" in Finder). Stop used to wait a fixed 250 ms on every
/// paste for this. Now it pastes at once when they are already up, which is the usual
/// case because transcription takes longer than a key tap, and polls otherwise.
/// ⇧ is ignored: "Return on ⇧" reads it, and ⌘⇧V is not a different paste in most apps.
@MainActor
enum PasteModifierGate {
    static let blocking: CGEventFlags = [.maskCommand, .maskAlternate, .maskControl]
    static let pollInterval: TimeInterval = 0.010
    static let maxWait: TimeInterval = 0.250

    nonisolated static func isClear(_ flags: CGEventFlags) -> Bool {
        flags.intersection(blocking).isEmpty
    }

    /// Runs `body` synchronously when the modifiers are already up, otherwise on the
    /// first poll that finds them up, or at `maxWait` at the latest.
    static func run(
        flags: @escaping @MainActor () -> CGEventFlags = { CGEventSource.flagsState(.hidSystemState) },
        now: @escaping @MainActor () -> TimeInterval = { CACurrentMediaTime() },
        maxWait: TimeInterval = PasteModifierGate.maxWait,
        schedule: @escaping @MainActor (TimeInterval, @escaping @MainActor () -> Void) -> Void = { delay, work in
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { MainActor.assumeIsolated { work() } }
        },
        _ body: @escaping @MainActor () -> Void
    ) {
        let start = now()
        func attempt() {
            if isClear(flags()) || now() - start >= maxWait {
                body()
                return
            }
            schedule(pollInterval) { attempt() }
        }
        attempt()
    }
}
