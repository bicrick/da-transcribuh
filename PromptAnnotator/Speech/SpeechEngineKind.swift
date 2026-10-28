import Foundation

/// Which transcription backend is active.
enum SpeechEngineKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case whisperKit
    case openAICompatible

    var id: String { rawValue }

    var title: String {
        switch self {
        case .whisperKit: return "On this Mac"
        case .openAICompatible: return "OpenAI-compatible server"
        }
    }

    var detail: String {
        switch self {
        case .whisperKit:
            return "WhisperKit, Parakeet (Highest), or your Core ML folders. Live captions for WhisperKit."
        case .openAICompatible:
            return "Final transcript only via /v1/audio/transcriptions. Live captions stay off."
        }
    }

    static let defaultsKey = "speech.engine"

    static func stored(_ raw: String?) -> SpeechEngineKind {
        SpeechEngineKind(rawValue: raw ?? "") ?? .whisperKit
    }
}
