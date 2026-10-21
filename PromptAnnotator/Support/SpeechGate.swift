import CoreGraphics
import Foundation

/// Decides that a session contained speech once the microphone stays above
/// the quiet floor for a couple of buffers. A single click decays away.
///
/// Optional quiet-room calibration replaces `defaultThreshold` process-wide
/// until reset; when unset, behavior matches the historic 0.28 floor.
enum SpeechGate {
    static let defaultThreshold: CGFloat = 0.28
    static let voicedNeeded = 2

    private static let lock = NSLock()
    private static var calibrated: CGFloat?

    /// Effective gate used by meters and silence-stop.
    static var threshold: CGFloat {
        lock.lock()
        defer { lock.unlock() }
        return calibrated ?? defaultThreshold
    }

    /// `nil` restores the launch default. Values are clamped to the calibration range.
    static func setCalibratedThreshold(_ value: CGFloat?) {
        lock.lock()
        defer { lock.unlock() }
        if let value {
            calibrated = min(
                QuietRoomCalibration.maximumThreshold,
                max(QuietRoomCalibration.minimumThreshold, value)
            )
        } else {
            calibrated = nil
        }
    }

    static func note(level: CGFloat, voicedBuffers: inout Int, heard: inout Bool) {
        guard !heard else { return }
        if level >= threshold {
            voicedBuffers += 1
            if voicedBuffers >= voicedNeeded {
                heard = true
            }
        } else if voicedBuffers > 0 {
            voicedBuffers -= 1
        }
    }
}
