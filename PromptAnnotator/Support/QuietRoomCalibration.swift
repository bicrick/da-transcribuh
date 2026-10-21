import AVFoundation
import Foundation

/// One-shot ambient sample used to tune `SpeechGate` / silence-stop without changing
/// defaults until the user calibrates. Revert by deleting this file and the
/// Configuration "Calibrate quiet room" controls / `speechGateThreshold` setting.
enum QuietRoomCalibration {
    static let sampleSeconds: TimeInterval = 1.6
    static let margin: CGFloat = 0.08
    static let minimumThreshold: CGFloat = 0.18
    static let maximumThreshold: CGFloat = 0.55

    enum Outcome: Equatable {
        case calibrated(threshold: CGFloat, ambient: CGFloat)
        case failed(String)
    }

    /// Maps dBFS meters onto the same 0…1 scale `AudioRecorder` uses.
    static func unitLevel(decibels: Float) -> CGFloat {
        let clamped = min(0, max(-50, decibels))
        return CGFloat((clamped + 50) / 50)
    }

    /// Ambient average plus a small margin, clamped so soft speech still clears the gate
    /// and a noisy room does not treat fans as speech forever.
    static func threshold(ambientLevel: CGFloat) -> CGFloat {
        min(maximumThreshold, max(minimumThreshold, ambientLevel + margin))
    }

    /// Listens briefly on the default input. Safe to call from the main actor; does not
    /// start a Mutter session. Disabled by the UI while a session is already recording.
    @MainActor
    static func sampleAmbient(duration: TimeInterval = sampleSeconds) async -> Outcome {
        let granted = await Permissions.requestMicrophone()
        guard granted else {
            return .failed("Microphone access is needed to measure the room.")
        }

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("mutter-quiet-room-\(UUID().uuidString).m4a")
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44_100,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.low.rawValue,
        ]
        let recorder: AVAudioRecorder
        do {
            recorder = try AVAudioRecorder(url: url, settings: settings)
        } catch {
            return .failed("The microphone isn't ready.")
        }
        recorder.isMeteringEnabled = true
        guard recorder.prepareToRecord(), recorder.record() else {
            return .failed("The microphone didn't start.")
        }
        defer {
            recorder.stop()
            try? FileManager.default.removeItem(at: url)
        }

        var sum: CGFloat = 0
        var count = 0
        let deadline = Date().addingTimeInterval(duration)
        while Date() < deadline {
            try? await Task.sleep(nanoseconds: 50_000_000)
            recorder.updateMeters()
            sum += unitLevel(decibels: recorder.averagePower(forChannel: 0))
            count += 1
        }
        guard count > 0 else {
            return .failed("Couldn't hear the room.")
        }
        let ambient = sum / CGFloat(count)
        let value = threshold(ambientLevel: ambient)
        return .calibrated(threshold: value, ambient: ambient)
    }
}
