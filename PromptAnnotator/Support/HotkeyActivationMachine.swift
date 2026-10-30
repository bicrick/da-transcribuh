import Foundation

/// How the Start/Stop shortcut behaves.
/// Wispr Flow model (docs.wisprflow.ai): hold to talk, double-tap within ~0.5s for
/// hands-free, a lone brief tap waits then cancels without pasting.
enum HotkeyBehavior: String, CaseIterable, Codable, Equatable, Hashable {
    /// Hold ≥ briefThreshold → push-to-talk; release stops. Double-tap within
    /// doubleTapWindow → hands-free. A single brief tap times out and cancels.
    case holdAndDoubleTap
    /// Hold to talk only. Brief release cancels without pasting. No hands-free latch.
    case holdOnly
    /// Classic toggle: each press flips recording. Combos like ⌥Space default here.
    case toggleOnly

    var title: String {
        switch self {
        case .holdAndDoubleTap: return "Hold to talk + double-tap hands-free"
        case .holdOnly: return "Hold to talk"
        case .toggleOnly: return "Toggle only"
        }
    }

    var detail: String {
        switch self {
        case .holdAndDoubleTap:
            return "Hold to dictate. Double-tap within half a second for hands-free. A quick single tap cancels."
        case .holdOnly:
            return "Hold to dictate, release to stop. Short taps cancel so accidental presses stay quiet."
        case .toggleOnly:
            return "Press once to start, press again to stop."
        }
    }
}

/// Pure press/hold/tap/double-tap state machine for single-key (and hold-mode) hotkeys.
/// Timing matches Wispr Flow (~0.5s brief / double-tap window).
struct HotkeyActivationMachine: Equatable {
    /// Hold shorter than this is a "tap" (Wispr: under half a second).
    static let briefThreshold: TimeInterval = 0.5
    /// Second tap must land within this window to become hands-free.
    static let doubleTapWindow: TimeInterval = 0.5

    enum Phase: Equatable {
        case idle
        /// Key is down; recording may already have started.
        case holding(downAt: TimeInterval)
        /// Brief release; waiting to see if a second tap arrives.
        case awaitingDoubleTap(releasedAt: TimeInterval)
        /// Hands-free recording (not holding).
        case handsFree
        /// Key down while hands-free (about to stop on release, or cancel if too quick).
        case handsFreeStopping(downAt: TimeInterval)
    }

    enum Edge: Equatable {
        case down(at: TimeInterval)
        case up(at: TimeInterval)
        /// Another key arrived while the hotkey was held (fn+arrow, etc.).
        case interrupted
        /// Double-tap wait expired without a second press.
        case doubleTapTimedOut
    }

    enum Action: Equatable {
        case startRecording
        case stopRecording
        /// Discard in-progress take; do not paste.
        case cancelRecording
        case armDoubleTapTimer(deadline: TimeInterval)
        case cancelDoubleTapTimer
    }

    private(set) var phase: Phase = .idle

    mutating func handle(_ edge: Edge, behavior: HotkeyBehavior) -> [Action] {
        switch behavior {
        case .toggleOnly:
            return handleToggle(edge)
        case .holdOnly:
            return handleHoldOnly(edge)
        case .holdAndDoubleTap:
            return handleHoldAndDoubleTap(edge)
        }
    }

    // MARK: - Toggle

    private mutating func handleToggle(_ edge: Edge) -> [Action] {
        switch edge {
        case .down:
            // Toggle fires on press.
            switch phase {
            case .idle:
                phase = .handsFree // "on" without holding
                return [.startRecording]
            case .handsFree, .handsFreeStopping, .holding, .awaitingDoubleTap:
                phase = .idle
                return [.cancelDoubleTapTimer, .stopRecording]
            }
        case .up, .interrupted, .doubleTapTimedOut:
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
            case .holding, .awaitingDoubleTap, .handsFree, .handsFreeStopping:
                return []
            }
        case .up(let at):
            guard case .holding(let downAt) = phase else { return [] }
            let duration = at - downAt
            phase = .idle
            if duration < Self.briefThreshold {
                return [.cancelRecording]
            }
            return [.stopRecording]
        case .interrupted:
            guard case .holding = phase else { return [] }
            phase = .idle
            return [.cancelRecording]
        case .doubleTapTimedOut:
            return []
        }
    }

    // MARK: - Hold + double-tap (Wispr)

    private mutating func handleHoldAndDoubleTap(_ edge: Edge) -> [Action] {
        switch edge {
        case .down(let at):
            switch phase {
            case .idle:
                phase = .holding(downAt: at)
                return [.startRecording]
            case .awaitingDoubleTap:
                // Second tap → hands-free. Keep the recording that already started.
                phase = .handsFree
                return [.cancelDoubleTapTimer]
            case .handsFree:
                phase = .handsFreeStopping(downAt: at)
                return []
            case .holding, .handsFreeStopping:
                return []
            }
        case .up(let at):
            switch phase {
            case .holding(let downAt):
                let duration = at - downAt
                if duration < Self.briefThreshold {
                    // Brief tap: wait for a possible second press before cancelling.
                    phase = .awaitingDoubleTap(releasedAt: at)
                    return [.armDoubleTapTimer(deadline: at + Self.doubleTapWindow)]
                }
                phase = .idle
                return [.stopRecording]
            case .handsFreeStopping(let downAt):
                let duration = at - downAt
                phase = .idle
                // Wispr: pressing hands-free again within half a second of starting cancels.
                if duration < Self.briefThreshold {
                    return [.cancelRecording]
                }
                return [.stopRecording]
            default:
                return []
            }
        case .interrupted:
            switch phase {
            case .holding, .awaitingDoubleTap:
                phase = .idle
                return [.cancelDoubleTapTimer, .cancelRecording]
            case .handsFreeStopping:
                // Interrupted while stopping — just go idle; leave recording to cancel.
                phase = .idle
                return [.cancelRecording]
            case .idle, .handsFree:
                return []
            }
        case .doubleTapTimedOut:
            guard case .awaitingDoubleTap = phase else { return [] }
            phase = .idle
            return [.cancelRecording]
        }
    }
}
