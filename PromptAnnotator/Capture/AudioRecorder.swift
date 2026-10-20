import AVFoundation
import Foundation
import os

final class AudioRecorder {
    private let log = Logger(subsystem: "com.bicrick.PromptAnnotator", category: "audio")
    private let engine = AVAudioEngine()
    private let captureQueue = DispatchQueue(label: "com.bicrick.PromptAnnotator.audio")
    private let sampleLock = NSLock()
    private var recorder: AVAudioRecorder?
    private var speechConverter: AVAudioConverter?
    private var speechFormat: AVAudioFormat?
    private var speechSamples: [Float] = []
    private var bandWindow: [Float] = []
    private var target: [CGFloat] = FrequencyBands.resting(WaveformSamples.count)
    private var bands: [CGFloat] = FrequencyBands.resting(WaveformSamples.count)
    private var quietFor: TimeInterval = 0
    private var lastSpectrumAt: CFTimeInterval = 0
    private var currentLevel: CGFloat = 0.12
    private var voicedBuffers = 0
    private var speechHeard = false
    private var tapInstalled = false
    private var usingEngine = false

    func start(url: URL) throws {
        sampleLock.lock()
        speechSamples = []
        bandWindow = []
        currentLevel = 0.12
        voicedBuffers = 0
        speechHeard = false
        target = FrequencyBands.resting(WaveformSamples.count)
        bands = target
        quietFor = 0
        lastSpectrumAt = 0
        sampleLock.unlock()

        try startRecorder(url: url)
        do {
            try startSpeechTap()
            usingEngine = true
        } catch {
            tearDownEngine()
            usingEngine = false
            log.error("Speech tap didn't start: \(error.localizedDescription, privacy: .public)")
        }
    }

    func stop() {
        tearDownEngine()
        recorder?.stop()
        recorder = nil
        usingEngine = false
    }

    func sampleCount() -> Int {
        sampleLock.lock()
        defer { sampleLock.unlock() }
        return speechSamples.count
    }

    func copySamples() -> [Float] {
        sampleLock.lock()
        defer { sampleLock.unlock() }
        return speechSamples
    }

    func heardSpeech() -> Bool {
        sampleLock.lock()
        defer { sampleLock.unlock() }
        return speechHeard
    }

    func latestLevel() -> CGFloat {
        sampleLock.lock()
        defer { sampleLock.unlock() }
        return currentLevel
    }

    /// One display step. The spectrum itself is updated on the audio queue; this only eases toward it.
    func sampleLevels(delta: TimeInterval = 1.0 / 60.0) -> [CGFloat] {
        var meterTarget: [CGFloat]?
        if !usingEngine, let recorder {
            recorder.updateMeters()
            let decibels = recorder.averagePower(forChannel: 0)
            let clamped = min(0, max(-50, decibels))
            let level = CGFloat((clamped + 50) / 50)
            currentLevel = level
            meterTarget = FrequencyBands.shaped(level: level, count: WaveformSamples.count)
            sampleLock.lock()
            SpeechGate.note(level: level, voicedBuffers: &voicedBuffers, heard: &speechHeard)
            sampleLock.unlock()
        }
        sampleLock.lock()
        if let meterTarget {
            target = meterTarget
        }
        bands = FrequencyBands.smooth(bands, toward: target, delta: delta)
        let snapshot = bands
        sampleLock.unlock()
        return snapshot
    }

    private func startRecorder(url: URL) throws {
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

    private func startSpeechTap() throws {
        let input = engine.inputNode
        let tapFormat = input.outputFormat(forBus: 0)
        guard tapFormat.sampleRate > 0, tapFormat.channelCount > 0 else {
            throw ExportError("The microphone format is not ready.")
        }
        guard let speechFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 16_000,
            channels: 1,
            interleaved: false
        ), let speechConverter = AVAudioConverter(from: tapFormat, to: speechFormat) else {
            throw ExportError("Couldn't prepare speech audio.")
        }

        self.speechConverter = speechConverter
        self.speechFormat = speechFormat
        input.installTap(onBus: 0, bufferSize: 1024, format: tapFormat) { [weak self] buffer, _ in
            guard let self, buffer.frameLength > 0 else { return }
            self.captureQueue.async {
                self.capture(buffer)
            }
        }
        tapInstalled = true
        engine.prepare()
        try engine.start()
    }

    private func tearDownEngine() {
        let touched = tapInstalled || engine.isRunning
        if tapInstalled {
            engine.inputNode.removeTap(onBus: 0)
            tapInstalled = false
        }
        if engine.isRunning {
            engine.stop()
        }
        captureQueue.sync {}
        speechConverter = nil
        speechFormat = nil
        if touched {
            engine.reset()
        }
    }

    private func capture(_ buffer: AVAudioPCMBuffer) {
        guard let speechConverter, let speechFormat,
              let speech = convert(buffer, with: speechConverter, format: speechFormat) else {
            return
        }
        let floats = Self.floats(from: speech)
        guard !floats.isEmpty else { return }
        let level = Self.unitLevel(floats)
        sampleLock.lock()
        speechSamples.append(contentsOf: floats)
        bandWindow.append(contentsOf: floats)
        if bandWindow.count > FrequencyBands.window + 2_048 {
            bandWindow.removeFirst(bandWindow.count - FrequencyBands.window)
        }
        let window = bandWindow
        currentLevel = level
        SpeechGate.note(level: level, voicedBuffers: &voicedBuffers, heard: &speechHeard)
        sampleLock.unlock()

        let silent = FrequencyBands.isSilent(window)
        let next = silent
            ? FrequencyBands.resting(WaveformSamples.count)
            : FrequencyBands.levels(samples: window, count: WaveformSamples.count)
        let now = CACurrentMediaTime()
        let delta = lastSpectrumAt == 0 ? (1.0 / 48.0) : min(0.08, max(0, now - lastSpectrumAt))
        lastSpectrumAt = now
        sampleLock.lock()
        target = FrequencyBands.follow(target, raw: next, silent: silent, quietFor: &quietFor, delta: delta)
        sampleLock.unlock()
    }

    private func convert(
        _ buffer: AVAudioPCMBuffer,
        with converter: AVAudioConverter,
        format: AVAudioFormat
    ) -> AVAudioPCMBuffer? {
        let ratio = format.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount((Double(buffer.frameLength) * ratio).rounded(.up)) + 64
        guard capacity > 0, let output = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else {
            return nil
        }
        var supplied = false
        var error: NSError?
        let status = converter.convert(to: output, error: &error) { _, outStatus in
            if supplied {
                outStatus.pointee = .noDataNow
                return nil
            }
            supplied = true
            outStatus.pointee = .haveData
            return buffer
        }
        guard error == nil, status != .error, output.frameLength > 0 else { return nil }
        return output
    }

    private static func floats(from buffer: AVAudioPCMBuffer) -> [Float] {
        guard let channel = buffer.floatChannelData?[0] else { return [] }
        return Array(UnsafeBufferPointer(start: channel, count: Int(buffer.frameLength)))
    }

    private static func unitLevel(_ samples: [Float]) -> CGFloat {
        guard !samples.isEmpty else { return 0.12 }
        var sum: Float = 0
        for sample in samples {
            sum += sample * sample
        }
        let rms = sqrt(sum / Float(samples.count))
        let decibels = 20 * log10(max(rms, 0.000_000_1))
        let clamped = min(0, max(-50, decibels))
        return CGFloat((clamped + 50) / 50)
    }
}
