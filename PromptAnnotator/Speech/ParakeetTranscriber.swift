import FluidAudio
import Foundation
import os

/// NVIDIA Parakeet via FluidAudio / Core ML (v2, v3, or Ultra).
/// Batch final transcript only — `consume` is a no-op (no live captions).
actor ParakeetTranscriber: Transcribing {
    /// Default English v2 (Settings default on Apple Silicon).
    static let variant = SpeechModelChoice.parakeetVariant
    static let modelVersion: AsrModelVersion = .v2
    /// Hugging Face repo for attribution / docs (v2).
    static let huggingFaceRepo = "FluidInference/parakeet-tdt-0.6b-v2-coreml"

    private static let readyFlag = ParakeetReadyFlag()
    private let log = Logger(subsystem: "com.bicrick.PromptAnnotator", category: "parakeet")

    private var manager: AsrManager?
    private var loadedVersion: AsrModelVersion?
    private var loading: Task<AsrManager, Error>?

    nonisolated static var isModelReady: Bool { readyFlag.isReady }

    nonisolated func resetLive() {}

    nonisolated func abandonLiveDecode() {}

    /// Maps a Settings variant onto FluidAudio’s `AsrModelVersion`.
    nonisolated static func modelVersion(for variant: String) -> AsrModelVersion? {
        switch variant {
        case SpeechModelChoice.parakeetVariant: return .v2
        case SpeechModelChoice.parakeetV3Variant: return .v3
        case SpeechModelChoice.parakeetUltraVariant: return .ultra
        default: return nil
        }
    }

    nonisolated static func huggingFaceRepo(for version: AsrModelVersion) -> String {
        switch version {
        case .v2: return "FluidInference/parakeet-tdt-0.6b-v2-coreml"
        case .v3: return "FluidInference/parakeet-tdt-0.6b-v3-coreml"
        case .ultra: return "FluidInference/parakeet-ultra-coreml"
        default: return huggingFaceRepo
        }
    }

    /// Active built-in Parakeet selection, if any.
    nonisolated static func selectedVersion(
        defaults: UserDefaults = .standard
    ) -> AsrModelVersion? {
        let choice = SpeechModelChoice.stored(defaults.string(forKey: SpeechModelChoice.defaultsKey))
        guard choice.backend == .fluidAudio else { return nil }
        return modelVersion(for: choice.variant)
    }

    /// Drops the resident manager so the next prepare/transcribe reloads weights.
    func unload() async {
        if let manager {
            await manager.cleanup()
        }
        manager = nil
        loadedVersion = nil
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
                let label = Self.selectedVersion().map { Self.variantLabel(for: $0) } ?? Self.variant
                return Transcript(words: [], model: label)
            }
        }

        let active = try await ensureManager(onProgress: onProgress)
        onProgress(.transcribing)

        var decoderState = TdtDecoderState.make(decoderLayers: await active.decoderLayerCount)
        let result: ASRResult
        if useSamples {
            result = try await active.transcribe(samples, decoderState: &decoderState)
        } else {
            result = try await active.transcribe(audioURL, decoderState: &decoderState)
        }

        let words = Self.words(from: result)
        let label = loadedVersion.map { Self.variantLabel(for: $0) } ?? Self.variant
        return Transcript(words: words, model: label)
    }

    nonisolated static func variantLabel(for version: AsrModelVersion) -> String {
        switch version {
        case .v2: return SpeechModelChoice.parakeetVariant
        case .v3: return SpeechModelChoice.parakeetV3Variant
        case .ultra: return SpeechModelChoice.parakeetUltraVariant
        default: return SpeechModelChoice.parakeetVariant
        }
    }

    nonisolated static func modelIsInstalled(version: AsrModelVersion = .v2) -> Bool {
        guard AppleSilicon.isCurrent else { return false }
        let directory = AsrModels.defaultCacheDirectory(for: version)
        return AsrModels.modelsExist(at: directory, version: version)
    }

    nonisolated static func modelIsInstalled(variant: String) -> Bool {
        guard let version = modelVersion(for: variant) else { return false }
        return modelIsInstalled(version: version)
    }

    nonisolated static func modelsFolder() -> URL {
        AsrModels.defaultCacheDirectory(for: modelVersion)
            .deletingLastPathComponent()
    }

    nonisolated static func cacheDirectory(for version: AsrModelVersion) -> URL {
        AsrModels.defaultCacheDirectory(for: version)
    }

    /// Downloads a Parakeet version when missing. Progress matches WhisperKit’s 0…1 fraction.
    static func fetch(
        version: AsrModelVersion = .v2,
        onProgress: @escaping @Sendable (Double) -> Void
    ) async throws -> URL {
        guard AppleSilicon.isCurrent else {
            throw ExportError("Parakeet needs an Apple Silicon Mac. Pick a WhisperKit model instead.")
        }
        let directory = try await AsrModels.download(
            version: version,
            progressHandler: { progress in
                onProgress(progress.fractionCompleted)
            }
        )
        return directory
    }

    static func fetch(
        variant: String,
        onProgress: @escaping @Sendable (Double) -> Void
    ) async throws -> URL {
        guard let version = modelVersion(for: variant) else {
            throw ExportError("Unknown Parakeet model: \(variant)")
        }
        return try await fetch(version: version, onProgress: onProgress)
    }

    /// Removes the on-disk Core ML bundle for a Parakeet variant. No-op if missing.
    nonisolated static func deleteInstalled(variant: String) throws {
        guard let version = modelVersion(for: variant) else { return }
        let directory = AsrModels.defaultCacheDirectory(for: version)
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: directory.path, isDirectory: &isDir), isDir.boolValue else {
            return
        }
        try FileManager.default.removeItem(at: directory)
        readyFlag.set(false)
    }

    private func ensureManager(
        onProgress: (@Sendable (SpeechProgress) -> Void)?
    ) async throws -> AsrManager {
        let version = Self.selectedVersion() ?? .v2

        if let manager, loadedVersion == version, await manager.isAvailable {
            Self.readyFlag.set(true)
            return manager
        }
        if loadedVersion != nil, loadedVersion != version {
            await unload()
        }
        if let loading {
            return try await loading.value
        }

        let task = Task { () throws -> AsrManager in
            do {
                if !Self.modelIsInstalled(version: version) {
                    onProgress?(.downloading(0))
                } else {
                    onProgress?(.preparing)
                }
                let models = try await AsrModels.downloadAndLoad(
                    version: version,
                    progressHandler: { progress in
                        onProgress?(.downloading(progress.fractionCompleted))
                    }
                )
                onProgress?(.preparing)
                let manager = AsrManager(config: .default)
                try await manager.loadModels(models)
                await self.store(manager, version: version)
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

    private func store(_ manager: AsrManager, version: AsrModelVersion) {
        self.manager = manager
        self.loadedVersion = version
        Self.readyFlag.set(true)
        log.notice("Parakeet \(Self.variantLabel(for: version), privacy: .public) is resident")
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
