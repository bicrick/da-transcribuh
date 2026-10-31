import Foundation

/// How the Start/Stop shortcut behaves.
enum HotkeyBehavior: String, CaseIterable, Codable, Equatable, Hashable {
    /// Tap to toggle hands-free; hold ≥ `holdThreshold` for push-to-talk.
    /// Raw value kept as `holdAndDoubleTap` so existing UserDefaults keep working.
    case holdAndDoubleTap
    /// Hold to talk only. Brief release cancels without pasting. No hands-free latch.
    case holdOnly
    /// Classic toggle: each press flips recording. Combos like ⌥Space default here.
    case toggleOnly

    var title: String {
        switch self {
        case .holdAndDoubleTap: return "Tap to toggle, hold to talk"
        case .holdOnly: return "Hold to talk"
        case .toggleOnly: return "Toggle only"
        }
    }

    var detail: String {
        switch self {
        case .holdAndDoubleTap:
            return "Quick tap starts or stops hands-free. Hold to talk, release to stop."
        case .holdOnly:
            return "Hold to dictate, release to stop. Short taps cancel so accidental presses stay quiet."
        case .toggleOnly:
            return "Press once to start, press again to stop."
        }
    }
}

/// Pure press / hold / tap state machine for single-key (and hold-mode) hotkeys.
/// Tap vs hold uses Superwhisper-style timing (~300ms).
struct HotkeyActivationMachine: Equatable {
    /// Hold at or past this duration is push-to-talk; shorter is a tap.
    static let holdThreshold: TimeInterval = 0.3

    enum Phase: Equatable {
        case idle
        /// Key down; not yet decided tap vs hold. No recording yet.
        case pending(downAt: TimeInterval)
        /// Push-to-talk: threshold crossed, recording while held.
        case holding(downAt: TimeInterval)
        /// Hands-free recording (not holding).
        case handsFree
        /// Key down while hands-free — stop on release (tap or hold).
        case handsFreeStopping(downAt: TimeInterval)
    }

    enum Edge: Equatable {
        case down(at: TimeInterval)
        case up(at: TimeInterval)
        /// Another key arrived while the hotkey was held (fn+arrow, emoji picker, etc.).
        case interrupted
        /// `holdThreshold` elapsed while still pending.
        case holdThresholdReached
    }

    enum Action: Equatable {
        case startRecording
        case stopRecording
        /// Discard in-progress take; do not paste.
        case cancelRecording
        case armHoldTimer(deadline: TimeInterval)
        case cancelHoldTimer
    }

    private(set) var phase: Phase = .idle

    mutating func handle(_ edge: Edge, behavior: HotkeyBehavior) -> [Action] {
        switch behavior {
        case .toggleOnly:
            return handleToggle(edge)
        case .holdOnly:
            return handleHoldOnly(edge)
        case .holdAndDoubleTap:
            return handleTapToggleHoldTalk(edge)
        }
    }

    // MARK: - Toggle

    private mutating func handleToggle(_ edge: Edge) -> [Action] {
        switch edge {
        case .down:
            switch phase {
            case .idle:
                phase = .handsFree
                return [.startRecording]
            case .handsFree, .handsFreeStopping, .holding, .pending:
                phase = .idle
                return [.cancelHoldTimer, .stopRecording]
            }
        case .up, .interrupted, .holdThresholdReached:
            return []
        }
    }

    // MARK: - Hold only

    private mutating func handleHoldOnly(_ edge: Edge) -> [Action] {
        switch edge {
        case .down(let at):
            switch phase {
            case .idle:
                phase = .holding(downAt: at)
                return [.startRecording]
            case .holding, .pending, .handsFree, .handsFreeStopping:
                return []
            }
        case .up(let at):
            guard case .holding(let downAt) = phase else { return [] }
            let duration = at - downAt
            phase = .idle
            if duration < Self.holdThreshold {
                return [.cancelRecording]
            }
            return [.stopRecording]
        case .interrupted:
            guard case .holding = phase else { return [] }
            phase = .idle
            return [.cancelRecording]
        case .holdThresholdReached:
            return []
        }
    }

    // MARK: - Tap toggle + hold PTT (Superwhisper-style)

    private mutating func handleTapToggleHoldTalk(_ edge: Edge) -> [Action] {
        switch edge {
        case .down(let at):
            switch phase {
            case .idle:
                phase = .pending(downAt: at)
                return [.armHoldTimer(deadline: at + Self.holdThreshold)]
            case .handsFree:
                phase = .handsFreeStopping(downAt: at)
                return []
            case .pending, .holding, .handsFreeStopping:
                return []
            }
        case .up:
            switch phase {
            case .pending:
                // Quick tap → toggle hands-free on.
                phase = .handsFree
                return [.cancelHoldTimer, .startRecording]
            case .holding:
                phase = .idle
                return [.stopRecording]
            case .handsFreeStopping:
                // Tap or hold while hands-free both stop on release.
                phase = .idle
                return [.stopRecording]
            case .idle, .handsFree:
                return []
            }
        case .holdThresholdReached:
            guard case .pending(let downAt) = phase else { return [] }
            // Crossed threshold while still held → push-to-talk.
            phase = .holding(downAt: downAt)
            return [.startRecording]
        case .interrupted:
            switch phase {
            case .pending:
                // Undecided tap: do not toggle.
                phase = .idle
                return [.cancelHoldTimer]
            case .holding:
                phase = .idle
                return [.cancelRecording]
            case .handsFreeStopping:
                phase = .idle
                return [.stopRecording]
            case .idle, .handsFree:
                return []
            }
        }
    }
}
