import Foundation

/// Ready / installed probes for the currently selected on-device model.
/// OpenAI-compatible engine is handled separately by callers.
enum SpeechModelStatus {
    /// Active built-in choice when no custom WhisperKit model is selected.
    nonisolated static func builtInChoice(
        defaults: UserDefaults = .standard
    ) -> SpeechModelChoice {
        SpeechModelChoice.stored(defaults.string(forKey: SpeechModelChoice.defaultsKey))
    }

    /// True when the selected on-device weights are complete on disk.
    nonisolated static func modelIsInstalled(defaults: UserDefaults = .standard) -> Bool {
        if CustomWhisperCatalog.selectedCustomID(defaults: defaults) != nil {
            return WhisperKitTranscriber.modelIsInstalled()
        }
        let choice = builtInChoice(defaults: defaults)
        switch choice.backend {
        case .whisperKit:
            return WhisperKitTranscriber.modelIsInstalled()
        case .fluidAudio:
            return ParakeetTranscriber.modelIsInstalled()
        }
    }

    /// True when the resident decoder for the selection is already loaded.
    nonisolated static var isModelReady: Bool {
        if CustomWhisperCatalog.selectedCustomID() != nil {
            return WhisperKitTranscriber.isModelReady
        }
        switch builtInChoice().backend {
        case .whisperKit:
            return WhisperKitTranscriber.isModelReady
        case .fluidAudio:
            return ParakeetTranscriber.isModelReady
        }
    }

    /// Live captions for WhisperKit built-ins / custom Core ML only.
    /// Parakeet and OpenAI-compatible are final-pass only.
    nonisolated static func liveCaptionsEnabled(defaults: UserDefaults = .standard) -> Bool {
        let engine = SpeechEngineKind.stored(defaults.string(forKey: SpeechEngineKind.defaultsKey))
        guard engine == .whisperKit else { return false }
        if CustomWhisperCatalog.selectedCustomID(defaults: defaults) != nil {
            return true
        }
        return builtInChoice(defaults: defaults).backend.supportsLiveCaptions
    }
}
