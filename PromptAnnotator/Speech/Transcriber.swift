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
    /// Stop pressed while a live decode is running: end that decode early and drop its
    /// words, so the final tail decode can start at once. The tail re-decodes the same audio.
    func abandonLiveDecode()
    func prepare() async
    /// Live decode of PCM whose index 0 is `bufferStart` seconds into the session.
    /// `absoluteEndCount` is the session-absolute sample index after `samples` (avoids float drift).
    func consume(samples: [Float], bufferStart: TimeInterval, absoluteEndCount: Int) async
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
    private let liveAbandoned = ReadyFlag()

    private var pipe: WhisperKit?
    private var loadedFolder: String?
    private var loading: Task<WhisperKit, Error>?
    private var decodeInFlight = false
    private var didLogConsumeError = false
    /// Security-scoped folder access kept alive while the custom model is loaded.
    private var scopedFolderURL: URL?

    nonisolated static var isModelReady: Bool { readyFlag.isReady }

    nonisolated func resetLive() {
        liveAbandoned.set(false)
        live.reset()
    }

    nonisolated func abandonLiveDecode() {
        liveAbandoned.set(true)
    }

    /// Drops the resident pipe so the next prepare/transcribe picks up a new selection.
    func unload() {
        pipe = nil
        loadedFolder = nil
        loading = nil
        stopScopedAccess()
        Self.readyFlag.set(false)
    }

    func prepare() async {
        let source = WhisperSourceResolver.resolve()
        do {
            let directory = try Self.modelsDirectory()
            if case .folder(let url, let label, _) = source {
                beginScopedAccess(url)
                guard WhisperModelLocator.isComplete(url) else { return }
                if pipe != nil, loadedFolder == url.path {
                    Self.readyFlag.set(true)
                    return
                }
                _ = try await load(folder: url, directory: directory, variant: label, repo: source.modelRepo)
                return
            }
            guard let installed = Self.installedModel(for: source) else { return }
            if pipe != nil, loadedFolder == installed.url.path {
                Self.readyFlag.set(true)
                return
            }
            _ = try await load(
                folder: installed.url,
                directory: directory,
                variant: installed.variant,
                repo: source.modelRepo
            )
        } catch {
            log.error("Model prepare failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    func consume(samples: [Float], bufferStart: TimeInterval, absoluteEndCount: Int) async {
        let shot = live.snapshot()
        let absoluteCount = max(absoluteEndCount, samples.count)
        guard samples.count >= WhisperKit.sampleRate, absoluteCount - shot.lastCount >= WhisperKit.sampleRate else { return }
        guard !decodeInFlight, !liveAbandoned.isReady, let pipe else { return }
        decodeInFlight = true
        defer { decodeInFlight = false }

        do {
            let decoded = try await decode(
                samples: samples,
                bufferStart: bufferStart,
                pipe: pipe,
                clipStart: shot.confirmedEnd,
                workers: 2,
                capWindow: true,
                abandon: liveAbandoned
            )
            // Cut short by stop: the words may be truncated ("you you you"), so keep none.
            // The final tail decode starts from the same confirmedEnd and covers this audio.
            guard !liveAbandoned.isReady else { return }
            // Holdback is relative to the decode window end — not the full buffer tail.
            // After the live ~45 s head-cap, using buffer duration would mark the whole
            // window stable (including the trailing second meant for revision).
            let stable = decoded.words.filter {
                $0.end <= decoded.windowEnd - LiveWordBuffer.holdback
            }
            let merged = LiveWordBuffer.appending(shot.confirmed, stable, confirmedEnd: shot.confirmedEnd)
            _ = live.save(
                generation: shot.generation,
                confirmed: merged.words,
                confirmedEnd: merged.end,
                lastCount: absoluteCount
            )
            didLogConsumeError = false
        } catch {
            // Advance lastCount so a stuck decode doesn't retry the same window every second.
            _ = live.save(
                generation: shot.generation,
                confirmed: shot.confirmed,
                confirmedEnd: shot.confirmedEnd,
                lastCount: absoluteCount
            )
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
            try Task.checkCancellation()
            try await Task.sleep(nanoseconds: 20_000_000)
        }

        let useSamples = samples.count >= WhisperKit.sampleRate / 4
        if !useSamples {
            let attributes = try FileManager.default.attributesOfItem(atPath: audioURL.path)
            let size = (attributes[.size] as? NSNumber)?.intValue ?? 0
            if size < 2048 {
                live.reset()
                return Transcript(words: [], model: Self.selectedVariant())
            }
        }

        decodeInFlight = true
        defer { decodeInFlight = false }
        let resolved = try await resolveModel(onProgress: onProgress)
        onProgress(.transcribing)
        let active = try await load(
            folder: resolved.url,
            directory: resolved.directory,
            variant: resolved.variant,
            repo: WhisperSourceResolver.resolve().modelRepo
        )

        if useSamples {
            let shot = live.snapshot()
            let tail: [TimedWord]
            do {
                // Final path must not apply the live ~45 s cap — only clip from confirmedEnd.
                tail = try await decode(
                    samples: samples,
                    bufferStart: 0,
                    pipe: active,
                    clipStart: shot.confirmedEnd,
                    workers: 4,
                    capWindow: false
                ).words
            } catch {
                log.error("Tail transcription failed: \(error.localizedDescription, privacy: .public)")
                // Fall back to full-file decode so the live holdback second isn't dropped.
                do {
                    return try await decodeFileMergingLive(
                        audioURL: audioURL,
                        pipe: active,
                        variant: resolved.variant
                    )
                } catch {
                    live.reset()
                    if shot.confirmed.isEmpty { throw error }
                    return Transcript(words: shot.confirmed, model: resolved.variant)
                }
            }
            let merged = LiveWordBuffer.appending(shot.confirmed, tail, confirmedEnd: shot.confirmedEnd)
            live.reset()
            return Transcript(words: merged.words, model: resolved.variant)
        }

        // Empty / capped PCM: decode the AAC file and merge any live-confirmed words.
        return try await decodeFileMergingLive(
            audioURL: audioURL,
            pipe: active,
            variant: resolved.variant
        )
    }

    private func decodeFileMergingLive(
        audioURL: URL,
        pipe: WhisperKit,
        variant: String
    ) async throws -> Transcript {
        let shot = live.snapshot()
        var options = Self.decodingOptions(chunking: .vad, windowClipTime: 1.0, workers: 4)
        if shot.confirmedEnd > 0.05 {
            options.clipTimestamps = [Float(shot.confirmedEnd)]
        }
        let results = try await pipe.transcribe(
            audioPath: audioURL.path,
            decodeOptions: options
        )
        let tail = Self.words(from: results)
        let merged = LiveWordBuffer.appending(shot.confirmed, tail, confirmedEnd: shot.confirmedEnd)
        live.reset()
        return Transcript(words: merged.words, model: variant)
    }

    nonisolated static func selectedVariant() -> String {
        WhisperSourceResolver.resolve().variantLabel
    }

    nonisolated static func modelsFolder() -> URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return support.appendingPathComponent("PromptAnnotator/Models", isDirectory: true)
    }

    nonisolated static func modelIsInstalled() -> Bool {
        let source = WhisperSourceResolver.resolve()
        switch source {
        case .folder(let url, _, _):
            return WhisperModelLocator.isComplete(url)
        case .builtIn, .huggingFace:
            return installedModel(for: source) != nil
        }
    }

    nonisolated static func liveCaptionsEnabled() -> Bool {
        SpeechModelStatus.liveCaptionsEnabled()
    }

    nonisolated private static func installedModel(for source: WhisperSource) -> WhisperModelFolder? {
        switch source {
        case .folder(let url, let label, _):
            guard WhisperModelLocator.isComplete(url) else { return nil }
            return WhisperModelFolder(url: url, variant: label)
        case .builtIn(let variant, _):
            return WhisperModelLocator.locate(in: modelsFolder(), variant: variant)
        case .huggingFace(_, let variant):
            return WhisperModelLocator.locate(in: modelsFolder(), variant: variant)
        }
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
        let source = WhisperSourceResolver.resolve()

        if case .folder(let url, let label, _) = source {
            beginScopedAccess(url)
            guard WhisperModelLocator.isComplete(url) else {
                throw ExportError("The custom Core ML folder is incomplete. Pick another model in Settings.")
            }
            if pipe == nil || loadedFolder != url.path {
                onProgress(.preparing)
                _ = try await load(folder: url, directory: directory, variant: label, repo: source.modelRepo)
            }
            return ResolvedModel(url: url, variant: label, directory: directory)
        }

        let variant = source.variantLabel
        let repo = source.modelRepo
        if let installed = WhisperModelLocator.locate(in: directory, variant: variant) {
            if pipe == nil || loadedFolder != installed.url.path {
                onProgress(.preparing)
                _ = try await load(
                    folder: installed.url,
                    directory: directory,
                    variant: installed.variant,
                    repo: repo
                )
            }
            return ResolvedModel(url: installed.url, variant: installed.variant, directory: directory)
        }

        onProgress(.downloading(0))
        let downloaded = try await Self.fetchResult(
            variant: variant,
            repo: repo,
            into: directory,
            onProgress: onProgress
        )
        onProgress(.preparing)
        _ = try await load(
            folder: downloaded.url,
            directory: directory,
            variant: downloaded.variant,
            repo: repo
        )
        return ResolvedModel(url: downloaded.url, variant: downloaded.variant, directory: directory)
    }

    /// Downloads the chosen model when it is not already complete. Tests do not call this.
    static func fetch(
        variant: String,
        repo: String = modelRepo,
        onProgress: @escaping @Sendable (Double) -> Void
    ) async throws -> URL {
        let directory = try modelsDirectory()
        if let installed = WhisperModelLocator.locate(in: directory, variant: variant) {
            return installed.url
        }
        let report: @Sendable (SpeechProgress) -> Void = { update in
            if case .downloading(let fraction) = update {
                onProgress(fraction)
            }
        }
        return try await fetchResult(variant: variant, repo: repo, into: directory, onProgress: report).url
    }

    /// Removes a built-in WhisperKit variant folder from disk when present.
    nonisolated static func deleteInstalled(variant: String) throws {
        let trimmed = variant.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard let installed = WhisperModelLocator.locate(in: modelsFolder(), variant: trimmed) else {
            return
        }
        try FileManager.default.removeItem(at: installed.url)
    }

    private static func fetchResult(
        variant: String,
        repo: String,
        into directory: URL,
        onProgress: @escaping @Sendable (SpeechProgress) -> Void
    ) async throws -> (url: URL, variant: String) {
        if variant == preferredVariant, repo == modelRepo {
            return try await downloadPreferred(into: directory, onProgress: onProgress)
        }
        let url = try await download(variant: variant, repo: repo, into: directory, onProgress: onProgress)
        return (url, variant)
    }

    private static func downloadPreferred(
        into directory: URL,
        onProgress: @escaping @Sendable (SpeechProgress) -> Void
    ) async throws -> (url: URL, variant: String) {
        do {
            let url = try await download(
                variant: preferredVariant,
                repo: modelRepo,
                into: directory,
                onProgress: onProgress
            )
            return (url, preferredVariant)
        } catch {
            let description = String(describing: error)
            let unresolved = description.contains("No models found") || description.contains("Multiple models found")
            guard unresolved else { throw error }
            let url = try await download(
                variant: fallbackVariant,
                repo: modelRepo,
                into: directory,
                onProgress: onProgress
            )
            return (url, fallbackVariant)
        }
    }

    private static func download(
        variant: String,
        repo: String,
        into directory: URL,
        onProgress: @escaping @Sendable (SpeechProgress) -> Void
    ) async throws -> URL {
        try await WhisperKit.download(
            variant: variant,
            downloadBase: directory,
            useBackgroundSession: false,
            from: repo,
            progressCallback: { progress in
                onProgress(.downloading(progress.fractionCompleted))
            }
        )
    }

    private func load(
        folder: URL,
        directory: URL,
        variant: String,
        repo: String
    ) async throws -> WhisperKit {
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
                let pipe = try await self.makePipe(
                    folder: folder,
                    directory: directory,
                    variant: variant,
                    repo: repo
                )
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

    private func beginScopedAccess(_ url: URL) {
        if scopedFolderURL?.path == url.path { return }
        stopScopedAccess()
        if url.startAccessingSecurityScopedResource() {
            scopedFolderURL = url
        }
    }

    private func stopScopedAccess() {
        if let scopedFolderURL {
            scopedFolderURL.stopAccessingSecurityScopedResource()
        }
        scopedFolderURL = nil
    }

    private func makePipe(
        folder: URL,
        directory: URL,
        variant: String,
        repo: String
    ) async throws -> WhisperKit {
        let config = WhisperKitConfig(
            model: variant,
            downloadBase: directory,
            modelRepo: repo,
            modelFolder: folder.path,
            tokenizerFolder: directory,
            computeOptions: ModelComputeOptions(
                melCompute: .cpuAndGPU,
                audioEncoderCompute: .cpuAndNeuralEngine,
                textDecoderCompute: .cpuAndNeuralEngine
            ),
            verbose: false,
            logLevel: .error,
            // Prefill Core ML special tokens so the first real decode is not cold.
            prewarm: true,
            load: true,
            download: false
        )
        return try await WhisperKit(config)
    }

    private func decode(
        samples: [Float],
        bufferStart: TimeInterval,
        pipe: WhisperKit,
        clipStart: TimeInterval,
        workers: Int,
        capWindow: Bool,
        abandon: ReadyFlag? = nil
    ) async throws -> (words: [TimedWord], windowEnd: TimeInterval) {
        let window = LiveSampleWindow.slice(
            samples: samples,
            bufferStart: bufferStart,
            clipStart: clipStart,
            sampleRate: WhisperKit.sampleRate,
            maxSeconds: capWindow ? LiveSampleWindow.maxSeconds : nil
        )
        let windowEnd = window.timeOffset
            + Double(window.samples.count) / Double(WhisperKit.sampleRate)
        guard !window.samples.isEmpty else { return ([], windowEnd) }

        // Live tails stay unclipped (`windowClipTime: 0`) so a sub-second remainder still decodes.
        var options = Self.decodingOptions(chunking: nil, windowClipTime: 0, workers: workers)
        let relativeClip = clipStart - window.timeOffset
        if relativeClip > 0.05 {
            options.clipTimestamps = [Float(relativeClip)]
        } else if window.samples.count > WhisperKit.sampleRate * 30 {
            options.chunkingStrategy = .vad
        }
        // Returning false from the progress callback ends the decode at the next token.
        let callback: TranscriptionCallback? = abandon.map { flag in
            { _ in flag.isReady ? false : nil }
        }
        let results = try await pipe.transcribe(
            audioArray: window.samples,
            decodeOptions: options,
            callback: callback
        )
        let words = Self.words(from: results)
        guard window.timeOffset > 0.000_5 else { return (words, windowEnd) }
        let shifted = words.map {
            TimedWord(text: $0.text, start: $0.start + window.timeOffset, end: $0.end + window.timeOffset)
        }
        return (shifted, windowEnd)
    }

    /// Shared decode settings. `suppressBlank` cuts silent-window hallucinations;
    /// `NonSpeechFilter` still scrubs any that slip through. Final/VAD uses WhisperKit's
    /// default `windowClipTime` (1.0); live decode passes 0 so short tails aren't padded away.
    /// Live paths use fewer workers to keep recording responsive on battery.
    private static func decodingOptions(
        chunking: ChunkingStrategy?,
        windowClipTime: Float,
        workers: Int
    ) -> DecodingOptions {
        // Settings / onboarding language. `auto` lets multilingual weights detect per window;
        // English-only (`.en`) weights ignore both fields inside WhisperKit.
        let stored = TranscriptionLanguage.stored(
            UserDefaults.standard.string(forKey: TranscriptionLanguage.defaultsKey)
        )
        let autoDetect = stored == TranscriptionLanguage.auto
        return DecodingOptions(
            language: autoDetect ? nil : stored,
            temperatureFallbackCount: 1,
            usePrefillPrompt: true,
            detectLanguage: autoDetect,
            skipSpecialTokens: true,
            wordTimestamps: true,
            windowClipTime: windowClipTime,
            suppressBlank: true,
            compressionRatioThreshold: 2.4,
            logProbThreshold: -1.0,
            noSpeechThreshold: 0.6,
            concurrentWorkerCount: max(1, workers),
            chunkingStrategy: chunking
        )
    }

    private static func words(from results: [TranscriptionResult]) -> [TimedWord] {
        let timed = results
            .flatMap(\.allWords)
            .map { TimedWord(text: $0.word, start: TimeInterval($0.start), end: TimeInterval($0.end)) }
            .sorted { lhs, rhs in
                if lhs.start == rhs.start { return lhs.end < rhs.end }
                return lhs.start < rhs.start
            }
        return NonSpeechFilter.filterWords(timed)
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
