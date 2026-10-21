import CoreGraphics
import Foundation

/// One-shot ambient sample used to tune `SpeechGate` / silence-stop without changing
/// defaults until the user calibrates. Revert by deleting this file and the
/// Configuration "Calibrate quiet room" controls / `speechGateThreshold` setting.
enum QuietRoomCalibration {
    static let sampleSeconds: TimeInterval = 1.6
    static let margin: CGFloat = 0.08
    static let minimumThreshold: CGFloat = 0.18
    static let maximumThreshold: CGFloat = 0.55

    private static let stateLock = NSLock()
    private static var sampling = false

    enum Outcome: Equatable {
        case calibrated(threshold: CGFloat, ambient: CGFloat)
        case failed(String)
    }

    /// True while Configuration is measuring the room (blocks starting a session).
    /// Armed for the whole critical section, including the mic-permission await.
    static var isInProgress: Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        return sampling
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

    /// Listens briefly through the same `AudioRecorder` level path a session uses
    /// (engine-tap PCM when available, otherwise recorder meters). Safe to call from
    /// the main actor; does not start a Mutter session. Disabled by the UI while a
    /// session is already recording or starting.
    @MainActor
    static func sampleAmbient(duration: TimeInterval = sampleSeconds) async -> Outcome {
        // Mark in-progress before any await so SessionController.begin cannot race in.
        stateLock.lock()
        if sampling {
            stateLock.unlock()
            return .failed("Calibration is already running.")
        }
        sampling = true
        stateLock.unlock()
        defer {
            stateLock.lock()
            sampling = false
            stateLock.unlock()
        }

        let session = SessionController.shared
        if session.isStartingSession || session.phase == .recording || session.isBusy {
            return .failed("Finish the current session first.")
        }

        let granted = await Permissions.requestMicrophone()
        guard granted else {
            return .failed("Microphone access is needed to measure the room.")
        }

        // Re-check after the mic dialog — a hotkey begin could have started meanwhile
        // only if isInProgress was ignored; still refuse if recording somehow began.
        if session.phase == .recording || session.isBusy {
            return .failed("Finish the current session first.")
        }

        // Match the session input device so the gate matches the mic the user will talk into.
        let settings = AppSettings.shared
        AudioInputs.beginSession(uid: settings.inputDeviceUID, raiseVolume: false)
        defer { AudioInputs.endSession() }

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("mutter-quiet-room-\(UUID().uuidString).m4a")
        let audio = AudioRecorder()
        do {
            try audio.start(url: url)
        } catch {
            try? FileManager.default.removeItem(at: url)
            return .failed("The microphone isn't ready.")
        }
        defer {
            audio.stop()
            try? FileManager.default.removeItem(at: url)
        }

        // Let the tap / meters produce a real floor before averaging.
        do {
            try await Task.sleep(nanoseconds: 120_000_000)
        } catch {
            return .failed("Calibration cancelled.")
        }

        var sum: CGFloat = 0
        var count = 0
        let deadline = Date().addingTimeInterval(duration)
        while Date() < deadline {
            do {
                try await Task.sleep(nanoseconds: 50_000_000)
            } catch {
                return .failed("Calibration cancelled.")
            }
            // Drives the recorder-meter fallback when the engine tap did not start.
            _ = audio.sampleLevels(delta: 0.05)
            sum += audio.latestLevel()
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
