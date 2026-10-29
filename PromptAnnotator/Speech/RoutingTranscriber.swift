import Foundation
import os

/// Routes `Transcribing` calls to WhisperKit, FluidAudio Parakeet, or an OpenAI-compatible final engine.
actor RoutingTranscriber: Transcribing {
    private let whisper: WhisperKitTranscriber
    private let parakeet: ParakeetTranscriber
    private let openAI: OpenAICompatibleTranscriber
    private let log = Logger(subsystem: "com.bicrick.PromptAnnotator", category: "speech-router")

    init(
        whisper: WhisperKitTranscriber = WhisperKitTranscriber(),
        parakeet: ParakeetTranscriber = ParakeetTranscriber(),
        openAI: OpenAICompatibleTranscriber = OpenAICompatibleTranscriber()
    ) {
        self.whisper = whisper
        self.parakeet = parakeet
        self.openAI = openAI
    }

    nonisolated var usesOpenAI: Bool {
        SpeechEngineKind.stored(UserDefaults.standard.string(forKey: SpeechEngineKind.defaultsKey))
            == .openAICompatible
    }

    /// Built-in Parakeet selection (not custom WhisperKit, not OpenAI).
    nonisolated var usesParakeet: Bool {
        guard !usesOpenAI else { return false }
        if CustomWhisperCatalog.selectedCustomID() != nil { return false }
        return SpeechModelChoice.stored(
            UserDefaults.standard.string(forKey: SpeechModelChoice.defaultsKey)
        ).backend == .fluidAudio
    }

    nonisolated func resetLive() {
        whisper.resetLive()
        parakeet.resetLive()
    }

    nonisolated func abandonLiveDecode() {
        whisper.abandonLiveDecode()
        parakeet.abandonLiveDecode()
    }

    func prepare() async {
        if usesOpenAI {
            await openAI.prepare()
            return
        }
        if usesParakeet {
            await whisper.unload()
            await parakeet.prepare()
            return
        }
        await parakeet.unload()
        await whisper.prepare()
    }

    func consume(samples: [Float], bufferStart: TimeInterval, absoluteEndCount: Int) async {
        guard !usesOpenAI, !usesParakeet else { return }
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
                await parakeet.unload()
                return try await whisper.transcribe(
                    audioURL: audioURL,
                    samples: samples,
                    onProgress: onProgress
                )
            }
        }

        if usesParakeet {
            do {
                return try await parakeet.transcribe(
                    audioURL: audioURL,
                    samples: samples,
                    onProgress: onProgress
                )
            } catch {
                log.error("Parakeet transcription failed, falling back to default WhisperKit: \(error.localizedDescription, privacy: .public)")
                await MainActor.run {
                    AppSettings.shared.fallBackToDefaultWhisperModel()
                }
                await parakeet.unload()
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
        await parakeet.unload()
        await prepare()
    }
}
