import CoreML
import Foundation
import os
import WhisperKit

enum SpeechProgress: Sendable, Equatable {
    case downloading(Double)
    case preparing
    case transcribing
}

struct Transcript: Sendable, Equatable {
    var words: [TimedWord]
    var model: String
}

protocol Transcribing: Sendable {
    func resetLive()
    func prepare() async
    func consume(samples: [Float]) async
    func transcribe(
        audioURL: URL,
        samples: [Float],
        onProgress: @escaping @Sendable (SpeechProgress) -> Void
    ) async throws -> Transcript
}

/// WhisperKit `small.en_217MB` stays loaded for the life of the process.
/// Speech captured during the session is decoded while recording is still going,
/// so stop only has to finish the last second. The model is fetched only when
/// the Core ML bundles are not already in Application Support.
actor WhisperKitTranscriber: Transcribing {
    static let preferredVariant = WhisperModelLocator.preferredVariant
    static let fallbackVariant = WhisperModelLocator.fallbackVariant
    static let modelRepo = "argmaxinc/whisperkit-coreml"

    private static let readyFlag = ReadyFlag()
    private let log = Logger(subsystem: "com.bicrick.PromptAnnotator", category: "speech")
    private let live = LiveWords()

    private var pipe: WhisperKit?
    private var loadedFolder: String?
    private var loading: Task<WhisperKit, Error>?
    private var decodeInFlight = false
    private var didLogConsumeError = false

    nonisolated static var isModelReady: Bool { readyFlag.isReady }

    nonisolated func resetLive() {
        live.reset()
    }

    func prepare() async {
        guard let installed = Self.installedModel() else { return }
        if pipe != nil, loadedFolder == installed.url.path {
            Self.readyFlag.set(true)
            return
        }
        do {
            let directory = try Self.modelsDirectory()
            _ = try await load(folder: installed.url, directory: directory, variant: installed.variant)
        } catch {
            log.error("Model prepare failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    func consume(samples: [Float]) async {
        let shot = live.snapshot()
        guard samples.count >= WhisperKit.sampleRate, samples.count - shot.lastCount >= WhisperKit.sampleRate else { return }
        guard !decodeInFlight, let pipe else { return }
        decodeInFlight = true
        defer { decodeInFlight = false }

        do {
            let words = try await decode(samples: samples, pipe: pipe, clipStart: shot.confirmedEnd)
            let duration = Double(samples.count) / Double(WhisperKit.sampleRate)
            let stable = words.filter { $0.end <= duration - LiveWordBuffer.holdback }
            let merged = LiveWordBuffer.appending(shot.confirmed, stable, confirmedEnd: shot.confirmedEnd)
            _ = live.save(
                generation: shot.generation,
                confirmed: merged.words,
                confirmedEnd: merged.end,
                lastCount: samples.count
            )
            didLogConsumeError = false
        } catch {
            if !didLogConsumeError {
                didLogConsumeError = true
                log.error("Live transcription failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    func transcribe(
        audioURL: URL,
        samples: [Float],
        onProgress: @escaping @Sendable (SpeechProgress) -> Void
    ) async throws -> Transcript {
        while decodeInFlight {
            try await Task.sleep(nanoseconds: 20_000_000)
        }

        let useSamples = samples.count >= WhisperKit.sampleRate / 4
        if !useSamples {
            let attributes = try FileManager.default.attributesOfItem(atPath: audioURL.path)
            let size = (attributes[.size] as? NSNumber)?.intValue ?? 0
            if size < 2048 {
                live.reset()
                return Transcript(words: [], model: Self.preferredVariant)
            }
        }

        decodeInFlight = true
        defer { decodeInFlight = false }
        let resolved = try await resolveModel(onProgress: onProgress)
        onProgress(.transcribing)
        let active = try await load(folder: resolved.url, directory: resolved.directory, variant: resolved.variant)

        if useSamples {
            let shot = live.snapshot()
            let tail: [TimedWord]
            do {
                tail = try await decode(samples: samples, pipe: active, clipStart: shot.confirmedEnd)
            } catch {
                live.reset()
                if shot.confirmed.isEmpty { throw error }
                log.error("Tail transcription failed: \(error.localizedDescription, privacy: .public)")
                return Transcript(words: shot.confirmed, model: resolved.variant)
            }
            let merged = LiveWordBuffer.appending(shot.confirmed, tail, confirmedEnd: shot.confirmedEnd)
            live.reset()
            return Transcript(words: merged.words, model: resolved.variant)
        }

        let options = DecodingOptions(
            language: "en",
            temperatureFallbackCount: 1,
            usePrefillPrompt: true,
            detectLanguage: false,
            skipSpecialTokens: true,
            wordTimestamps: true,
            windowClipTime: 0,
            concurrentWorkerCount: 4,
            chunkingStrategy: .vad
        )
        let results = try await active.transcribe(audioPath: audioURL.path, decodeOptions: options)
        live.reset()
        return Transcript(words: Self.words(from: results), model: resolved.variant)
    }

    nonisolated static func modelsFolder() -> URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return support.appendingPathComponent("PromptAnnotator/Models", isDirectory: true)
    }

    nonisolated static func modelIsInstalled() -> Bool {
        installedModel() != nil
    }

    nonisolated private static func installedModel() -> WhisperModelFolder? {
        WhisperModelLocator.locate(in: modelsFolder())
    }

    private static func modelsDirectory() throws -> URL {
        let directory = modelsFolder()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private struct ResolvedModel {
        var url: URL
        var variant: String
        var directory: URL
    }

    private func resolveModel(
        onProgress: @escaping @Sendable (SpeechProgress) -> Void
    ) async throws -> ResolvedModel {
        let directory = try Self.modelsDirectory()
        if let installed = WhisperModelLocator.locate(in: directory) {
            if pipe == nil || loadedFolder != installed.url.path {
                onProgress(.preparing)
                _ = try await load(folder: installed.url, directory: directory, variant: installed.variant)
            }
            return ResolvedModel(url: installed.url, variant: installed.variant, directory: directory)
        }

        onProgress(.downloading(0))
        let downloaded = try await Self.download(into: directory, onProgress: onProgress)
        onProgress(.preparing)
        _ = try await load(folder: downloaded.url, directory: directory, variant: downloaded.variant)
        return ResolvedModel(url: downloaded.url, variant: downloaded.variant, directory: directory)
    }

    private static func download(
        into directory: URL,
        onProgress: @escaping @Sendable (SpeechProgress) -> Void
    ) async throws -> (url: URL, variant: String) {
        do {
            let url = try await download(variant: preferredVariant, into: directory, onProgress: onProgress)
            return (url, preferredVariant)
        } catch {
            let description = String(describing: error)
            let unresolved = description.contains("No models found") || description.contains("Multiple models found")
            guard unresolved else { throw error }
            let url = try await download(variant: fallbackVariant, into: directory, onProgress: onProgress)
            return (url, fallbackVariant)
        }
    }

    private static func download(
        variant: String,
        into directory: URL,
        onProgress: @escaping @Sendable (SpeechProgress) -> Void
    ) async throws -> URL {
        try await WhisperKit.download(
            variant: variant,
            downloadBase: directory,
            useBackgroundSession: false,
            from: modelRepo,
            progressCallback: { progress in
                onProgress(.downloading(progress.fractionCompleted))
            }
        )
    }

    private func load(folder: URL, directory: URL, variant: String) async throws -> WhisperKit {
        if let pipe, loadedFolder == folder.path {
            Self.readyFlag.set(true)
            return pipe
        }
        if let loading {
            let pipe = try await loading.value
            if loadedFolder == folder.path {
                return pipe
            }
        }
        let task = Task { () throws -> WhisperKit in
            do {
                let pipe = try await self.makePipe(folder: folder, directory: directory, variant: variant)
                await self.store(pipe, folder: folder)
                return pipe
            } catch {
                self.log.error("Model load failed: \(error.localizedDescription, privacy: .public)")
                throw error
            }
        }
        loading = task
        defer { loading = nil }
        return try await task.value
    }

    private func store(_ pipe: WhisperKit, folder: URL) {
        self.pipe = pipe
        loadedFolder = folder.path
        Self.readyFlag.set(true)
        log.notice("Whisper model is resident")
    }

    private func makePipe(folder: URL, directory: URL, variant: String) async throws -> WhisperKit {
        let config = WhisperKitConfig(
            model: variant,
            downloadBase: directory,
            modelRepo: Self.modelRepo,
            modelFolder: folder.path,
            tokenizerFolder: directory,
            computeOptions: ModelComputeOptions(
                melCompute: .cpuAndGPU,
                audioEncoderCompute: .cpuAndNeuralEngine,
                textDecoderCompute: .cpuAndNeuralEngine
            ),
            verbose: false,
            logLevel: .error,
            prewarm: false,
            load: true,
            download: false
        )
        return try await WhisperKit(config)
    }

    private func decode(samples: [Float], pipe: WhisperKit, clipStart: TimeInterval) async throws -> [TimedWord] {
        var options = DecodingOptions(
            language: "en",
            temperatureFallbackCount: 1,
            usePrefillPrompt: true,
            detectLanguage: false,
            skipSpecialTokens: true,
            wordTimestamps: true,
            windowClipTime: 0,
            concurrentWorkerCount: 4
        )
        if clipStart > 0.05 {
            options.clipTimestamps = [Float(clipStart)]
        } else if samples.count > WhisperKit.sampleRate * 30 {
            options.chunkingStrategy = .vad
        }
        let results = try await pipe.transcribe(audioArray: samples, decodeOptions: options)
        return Self.words(from: results)
    }

    private static func words(from results: [TranscriptionResult]) -> [TimedWord] {
        results
            .flatMap(\.allWords)
            .map { TimedWord(text: $0.word, start: TimeInterval($0.start), end: TimeInterval($0.end)) }
            .sorted { lhs, rhs in
                if lhs.start == rhs.start { return lhs.end < rhs.end }
                return lhs.start < rhs.start
            }
    }
}

private final class ReadyFlag: @unchecked Sendable {
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

private final class LiveWords: @unchecked Sendable {
    struct Snapshot {
        var generation: Int
        var confirmed: [TimedWord]
        var confirmedEnd: TimeInterval
        var lastCount: Int
    }

    private let lock = NSLock()
    private var generation = 0
    private var confirmed: [TimedWord] = []
    private var confirmedEnd: TimeInterval = 0
    private var lastCount = 0

    func reset() {
        lock.lock()
        generation += 1
        confirmed = []
        confirmedEnd = 0
        lastCount = 0
        lock.unlock()
    }

    func snapshot() -> Snapshot {
        lock.lock()
        defer { lock.unlock() }
        return Snapshot(
            generation: generation,
            confirmed: confirmed,
            confirmedEnd: confirmedEnd,
            lastCount: lastCount
        )
    }

    func save(generation: Int, confirmed: [TimedWord], confirmedEnd: TimeInterval, lastCount: Int) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard self.generation == generation else { return false }
        self.confirmed = confirmed
        self.confirmedEnd = confirmedEnd
        self.lastCount = lastCount
        return true
    }
}
