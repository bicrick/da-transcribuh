import AVFoundation
import Foundation

final class AudioRecorder {
    private var recorder: AVAudioRecorder?
    private var history: [CGFloat] = Array(repeating: 0.12, count: 5)

    var levels: [CGFloat] { history }

    func start(url: URL) throws {
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 48_000,
            AVNumberOfChannelsKey: 1,
            AVEncoderBitRateKey: 96_000,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
        ]
        let recorder = try AVAudioRecorder(url: url, settings: settings)
        recorder.isMeteringEnabled = true
        recorder.prepareToRecord()
        guard recorder.record() else {
            throw ExportError("The microphone didn't start recording.")
        }
        self.recorder = recorder
    }

    func stop() {
        recorder?.stop()
        recorder = nil
    }

    func sampleLevels() -> [CGFloat] {
        guard let recorder else { return history }
        recorder.updateMeters()
        let decibels = recorder.averagePower(forChannel: 0)
        let clamped = min(0, max(-50, decibels))
        let level = CGFloat((clamped + 50) / 50)
        history.removeFirst()
        history.append(max(0.08, level))
        return history
    }
}
