import AVFoundation
import Darwin
import Foundation
import os

struct SpeechBufferSnapshot: Sendable {
    /// PCM whose index 0 is `timeOffset` seconds into the session.
    var samples: [Float]
    var timeOffset: TimeInterval
    /// Session-absolute sample count through the end of `samples` (integer; no float round-trip).
    var absoluteCount: Int
    /// `true` when the in-memory buffer still covers the whole take (no trim).
    var isComplete: Bool
}

/// Mic capture + PCM ring. Mutable state is guarded by `sampleLock` / the capture queue.
final class AudioRecorder: @unchecked Sendable {
    private let log = Logger(subsystem: "com.bicrick.PromptAnnotator", category: "audio")
    private let engine = AVAudioEngine()
    private let captureQueue = DispatchQueue(label: "com.bicrick.PromptAnnotator.audio")
    private let sampleLock = NSLock()
    private var recorder: AVAudioRecorder?
    private var speechConverter: AVAudioConverter?
    private var speechFormat: AVAudioFormat?
    private var speechSamples: [Float] = []
    /// Samples dropped from the front of `speechSamples` (session-absolute index of retained [0]).
    private var droppedSpeechSamples = 0
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

    /// Soft cap on retained PCM (~10 min @ 16 kHz mono ≈ 38 MB). Longer takes keep the AAC file.
    private static let maxRetainedSamples = 16_000 * 60 * 10
    /// Only compact when this far over the cap so `removeFirst` is rare on the audio queue.
    private static let retainSlack = 16_000 * 5

    func start(url: URL) throws {
        sampleLock.lock()
        speechSamples = []
        droppedSpeechSamples = 0
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
        return droppedSpeechSamples + speechSamples.count
    }

    func copySamples() -> [Float] {
        sampleLock.lock()
        defer { sampleLock.unlock() }
        return speechSamples
    }

    /// Thread-safe snapshot for live / final speech paths.
    func copySpeechBuffer() -> SpeechBufferSnapshot {
        sampleLock.lock()
        defer { sampleLock.unlock() }
        let absolute = droppedSpeechSamples + speechSamples.count
        let offset = Double(droppedSpeechSamples) / 16_000.0
        return SpeechBufferSnapshot(
            samples: speechSamples,
            timeOffset: offset,
            absoluteCount: absolute,
            isComplete: droppedSpeechSamples == 0
        )
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
            meterTarget = FrequencyBands.shaped(level: level, count: WaveformSamples.count)
            sampleLock.lock()
            currentLevel = level
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
            // Tap buffers are only valid inside this callback — copy before leaving.
            guard let owned = Self.copyPCMBuffer(buffer) else { return }
            self.captureQueue.async {
                self.capture(owned)
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
        Self.trimSpeechSamplesIfNeeded(
            samples: &speechSamples,
            dropped: &droppedSpeechSamples,
            maxCount: Self.maxRetainedSamples,
            slack: Self.retainSlack
        )
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

    /// Owns a PCM copy so async capture never reads the engine's recycled tap buffer.
    private static func copyPCMBuffer(_ buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        guard let copy = AVAudioPCMBuffer(pcmFormat: buffer.format, frameCapacity: buffer.frameLength) else {
            return nil
        }
        copy.frameLength = buffer.frameLength
        let source = UnsafeMutableAudioBufferListPointer(buffer.mutableAudioBufferList)
        let destination = UnsafeMutableAudioBufferListPointer(copy.mutableAudioBufferList)
        for (src, dst) in zip(source, destination) {
            guard let srcData = src.mData, let dstData = dst.mData else { continue }
            memcpy(dstData, srcData, Int(src.mDataByteSize))
            dst.mDataByteSize = src.mDataByteSize
        }
        return copy
    }

    /// Drops the oldest PCM once the buffer is `slack` past `maxCount`.
    static func trimSpeechSamplesIfNeeded(
        samples: inout [Float],
        dropped: inout Int,
        maxCount: Int,
        slack: Int
    ) {
        let limit = maxCount + max(0, slack)
        guard samples.count > limit else { return }
        let overflow = samples.count - maxCount
        samples.removeFirst(overflow)
        dropped += overflow
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
