import Foundation
import os

/// Routes `Transcribing` calls to WhisperKit or an OpenAI-compatible final engine.
actor RoutingTranscriber: Transcribing {
    private let whisper: WhisperKitTranscriber
    private let openAI: OpenAICompatibleTranscriber
    private let log = Logger(subsystem: "com.bicrick.PromptAnnotator", category: "speech-router")

    init(
        whisper: WhisperKitTranscriber = WhisperKitTranscriber(),
        openAI: OpenAICompatibleTranscriber = OpenAICompatibleTranscriber()
    ) {
        self.whisper = whisper
        self.openAI = openAI
    }

    nonisolated var usesOpenAI: Bool {
        SpeechEngineKind.stored(UserDefaults.standard.string(forKey: SpeechEngineKind.defaultsKey))
            == .openAICompatible
    }

    nonisolated func resetLive() {
        whisper.resetLive()
        // OpenAI has no live buffer.
    }

    nonisolated func abandonLiveDecode() {
        whisper.abandonLiveDecode()
    }

    func prepare() async {
        if usesOpenAI {
            await openAI.prepare()
            return
        }
        await whisper.prepare()
    }

    func consume(samples: [Float], bufferStart: TimeInterval, absoluteEndCount: Int) async {
        guard !usesOpenAI else { return }
        await whisper.consume(
            samples: samples,
            bufferStart: bufferStart,
            absoluteEndCount: absoluteEndCount
        )
    }

    func transcribe(
        audioURL: URL,
        samples: [Float],
        onProgress: @escaping @Sendable (SpeechProgress) -> Void
    ) async throws -> Transcript {
        if usesOpenAI {
            do {
                return try await openAI.transcribe(
                    audioURL: audioURL,
                    samples: samples,
                    onProgress: onProgress
                )
            } catch {
                log.error("OpenAI transcription failed, falling back to WhisperKit: \(error.localizedDescription, privacy: .public)")
                // One-shot on-device fallback for this stop. Engine selection stays as configured.
                await MainActor.run {
                    AppSettings.shared.fallBackToDefaultWhisperModel()
                }
                await whisper.unload()
                return try await whisper.transcribe(
                    audioURL: audioURL,
                    samples: samples,
                    onProgress: onProgress
                )
            }
        }
        do {
            return try await whisper.transcribe(
                audioURL: audioURL,
                samples: samples,
                onProgress: onProgress
            )
        } catch {
            // Custom / HF failures: clear the bad selection and retry the built-in default once.
            let usingCustom = CustomWhisperCatalog.selectedCustomID() != nil
            guard usingCustom else { throw error }
            log.error("Custom WhisperKit model failed, falling back to default: \(error.localizedDescription, privacy: .public)")
            await MainActor.run {
                AppSettings.shared.fallBackToDefaultWhisperModel()
            }
            await whisper.unload()
            return try await whisper.transcribe(
                audioURL: audioURL,
                samples: samples,
                onProgress: onProgress
            )
        }
    }

    func reloadSelection() async {
        await whisper.unload()
        await prepare()
    }
}
