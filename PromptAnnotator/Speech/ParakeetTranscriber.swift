import FluidAudio
import Foundation
import os

/// NVIDIA Parakeet TDT 0.6B v2 (English) via FluidAudio / Core ML.
/// Batch final transcript only — `consume` is a no-op (no live captions).
actor ParakeetTranscriber: Transcribing {
    static let variant = SpeechModelChoice.parakeetVariant
    static let modelVersion: AsrModelVersion = .v2
    /// Hugging Face repo for attribution / docs.
    static let huggingFaceRepo = "FluidInference/parakeet-tdt-0.6b-v2-coreml"

    private static let readyFlag = ParakeetReadyFlag()
    private let log = Logger(subsystem: "com.bicrick.PromptAnnotator", category: "parakeet")

    private var manager: AsrManager?
    private var loading: Task<AsrManager, Error>?

    nonisolated static var isModelReady: Bool { readyFlag.isReady }

    nonisolated func resetLive() {}

    nonisolated func abandonLiveDecode() {}

    /// Drops the resident manager so the next prepare/transcribe reloads weights.
    func unload() {
        manager?.cleanup()
        manager = nil
        loading = nil
        Self.readyFlag.set(false)
    }

    func prepare() async {
        do {
            _ = try await ensureManager(onProgress: nil)
        } catch {
            log.error("Parakeet prepare failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// No live path for batch Parakeet — island captions stay empty until stop.
    func consume(samples: [Float], bufferStart: TimeInterval, absoluteEndCount: Int) async {}

    func transcribe(
        audioURL: URL,
        samples: [Float],
        onProgress: @escaping @Sendable (SpeechProgress) -> Void
    ) async throws -> Transcript {
        let useSamples = samples.count >= 4_000
        if !useSamples {
            let attributes = try FileManager.default.attributesOfItem(atPath: audioURL.path)
            let size = (attributes[.size] as? NSNumber)?.intValue ?? 0
            if size < 2048 {
                return Transcript(words: [], model: Self.variant)
            }
        }

        let active = try await ensureManager(onProgress: onProgress)
        onProgress(.transcribing)

        var decoderState = TdtDecoderState.make(decoderLayers: active.decoderLayerCount)
        let result: ASRResult
        if useSamples {
            result = try await active.transcribe(samples, decoderState: &decoderState)
        } else {
            result = try await active.transcribe(audioURL, decoderState: &decoderState)
        }

        let words = Self.words(from: result)
        return Transcript(words: words, model: Self.variant)
    }

    nonisolated static func modelIsInstalled() -> Bool {
        guard AppleSilicon.isCurrent else { return false }
        let directory = AsrModels.defaultCacheDirectory(for: modelVersion)
        return AsrModels.modelsExist(at: directory, version: modelVersion)
    }

    nonisolated static func modelsFolder() -> URL {
        AsrModels.defaultCacheDirectory(for: modelVersion)
            .deletingLastPathComponent()
    }

    /// Downloads Parakeet v2 when missing. Progress matches WhisperKit’s 0…1 fraction.
    static func fetch(
        onProgress: @escaping @Sendable (Double) -> Void
    ) async throws -> URL {
        guard AppleSilicon.isCurrent else {
            throw ExportError("Parakeet needs an Apple Silicon Mac. Pick Fast or Balanced instead.")
        }
        let directory = try await AsrModels.download(
            version: modelVersion,
            progressHandler: { progress in
                onProgress(progress.fractionCompleted)
            }
        )
        return directory
    }

    private func ensureManager(
        onProgress: (@Sendable (SpeechProgress) -> Void)?
    ) async throws -> AsrManager {
        if let manager, manager.isAvailable {
            Self.readyFlag.set(true)
            return manager
        }
        if let loading {
            return try await loading.value
        }

        let task = Task { () throws -> AsrManager in
            do {
                if !Self.modelIsInstalled() {
                    onProgress?(.downloading(0))
                } else {
                    onProgress?(.preparing)
                }
                let models = try await AsrModels.downloadAndLoad(
                    version: Self.modelVersion,
                    progressHandler: { progress in
                        onProgress?(.downloading(progress.fractionCompleted))
                    }
                )
                onProgress?(.preparing)
                let manager = AsrManager(config: .default)
                try await manager.loadModels(models)
                await self.store(manager)
                return manager
            } catch {
                self.log.error("Parakeet load failed: \(error.localizedDescription, privacy: .public)")
                throw error
            }
        }
        loading = task
        defer { loading = nil }
        return try await task.value
    }

    private func store(_ manager: AsrManager) {
        self.manager = manager
        Self.readyFlag.set(true)
        log.notice("Parakeet model is resident")
    }

    private static func words(from result: ASRResult) -> [TimedWord] {
        let timed: [TimedWord]
        if let tokens = result.tokenTimings, !tokens.isEmpty {
            timed = buildWordTimings(from: tokens).map {
                TimedWord(text: $0.word, start: $0.startTime, end: $0.endTime)
            }
        } else {
            // Fallback: one span for the whole clip when timings are missing.
            let text = result.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return [] }
            let pieces = text.split(whereSeparator: \.isWhitespace).map(String.init)
            guard !pieces.isEmpty else { return [] }
            let duration = max(result.duration, 0.05)
            let step = duration / Double(pieces.count)
            timed = pieces.enumerated().map { index, word in
                let start = Double(index) * step
                return TimedWord(text: word, start: start, end: start + step)
            }
        }
        return NonSpeechFilter.filterWords(timed)
    }
}

private final class ParakeetReadyFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var ready = false

    var isReady: Bool {
        lock.lock()
        defer { lock.unlock() }
        return ready
    }

    func set(_ ready: Bool) {
        lock.lock()
        self.ready = ready
        lock.unlock()
    }
}
