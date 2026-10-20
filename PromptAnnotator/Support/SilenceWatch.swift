import CoreGraphics
import Foundation

/// Tracks quiet time after speech has been heard. A limit of zero leaves the session running.
struct SilenceWatch: Equatable {
    var accumulated: TimeInterval = 0

    mutating func tick(level: CGFloat, heardSpeech: Bool, limit: TimeInterval, delta: TimeInterval) -> Bool {
        guard limit > 0, heardSpeech else {
            accumulated = 0
            return false
        }
        if level < SpeechGate.threshold {
            accumulated += delta
        } else {
            accumulated = 0
        }
        return accumulated >= limit
    }
}

enum SessionLimits {
    static func reachedMax(elapsed: TimeInterval, minutes: Double) -> Bool {
        guard minutes > 0 else { return false }
        return elapsed >= minutes * 60
    }
}
