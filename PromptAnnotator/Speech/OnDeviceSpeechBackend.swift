import Foundation

/// On-device decoder behind a built-in `SpeechModelChoice`.
/// Distinct from `SpeechEngineKind`, which is the Settings “Engine” toggle
/// (local Mac vs OpenAI-compatible server).
enum OnDeviceSpeechBackend: String, Codable, CaseIterable, Sendable {
    case whisperKit
    case fluidAudio

    var title: String {
        switch self {
        case .whisperKit: return "WhisperKit"
        case .fluidAudio: return "FluidAudio"
        }
    }

    /// Live captions need a streaming/partial path. FluidAudio Parakeet is batch-only here.
    var supportsLiveCaptions: Bool {
        switch self {
        case .whisperKit: return true
        case .fluidAudio: return false
        }
    }
}

/// Compile-time Apple Silicon probe (matches FluidAudio’s gate).
enum AppleSilicon {
    static var isCurrent: Bool {
        #if arch(arm64)
        return true
        #else
        return false
        #endif
    }
}
