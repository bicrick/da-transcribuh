import Foundation
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
    func transcribe(
        audioURL: URL,
        onProgress: @escaping @Sendable (SpeechProgress) -> Void
    ) async throws -> Transcript
}

/// WhisperKit `small.en_217MB` from `argmaxinc/whisperkit-coreml`
/// (`openai_whisper-small.en_217MB`). Falls back to `small.en` only when that
/// variant name does not resolve in the model repo.
actor WhisperKitTranscriber: Transcribing {
    static let preferredVariant = "small.en_217MB"
    static let fallbackVariant = "small.en"
    static let modelRepo = "argmaxinc/whisperkit-coreml"

    private var pipe: WhisperKit?
    private var loadedFolder: String?

    func transcribe(
        audioURL: URL,
        onProgress: @escaping @Sendable (SpeechProgress) -> Void
    ) async throws -> Transcript {
        let attributes = try FileManager.default.attributesOfItem(atPath: audioURL.path)
        let size = (attributes[.size] as? NSNumber)?.intValue ?? 0
        if size < 2048 {
            return Transcript(words: [], model: Self.preferredVariant)
        }

        onProgress(.downloading(0))
        let directory = try Self.modelsDirectory()
        let resolved = try await Self.download(into: directory, onProgress: onProgress)
        onProgress(.preparing)
        let pipe = try await load(folder: resolved.url, directory: directory)
        onProgress(.transcribing)

        let options = DecodingOptions(
            language: "en",
            skipSpecialTokens: true,
            wordTimestamps: true,
            chunkingStrategy: .vad
        )
        let results = try await pipe.transcribe(audioPath: audioURL.path, decodeOptions: options)
        let words = results
            .flatMap(\.allWords)
            .map {
                TimedWord(text: $0.word, start: TimeInterval($0.start), end: TimeInterval($0.end))
            }
            .sorted { $0.start < $1.start }
        return Transcript(words: words, model: resolved.variant)
    }

    private static func modelsDirectory() throws -> URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let directory = support.appendingPathComponent("PromptAnnotator/Models", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
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

    private func load(folder: URL, directory: URL) async throws -> WhisperKit {
        if let pipe, loadedFolder == folder.path {
            return pipe
        }
        let config = WhisperKitConfig(
            model: Self.preferredVariant,
            downloadBase: directory,
            modelRepo: Self.modelRepo,
            modelFolder: folder.path,
            verbose: false,
            logLevel: .error,
            prewarm: false,
            load: true,
            download: false
        )
        let pipe = try await WhisperKit(config)
        self.pipe = pipe
        loadedFolder = folder.path
        return pipe
    }
}
