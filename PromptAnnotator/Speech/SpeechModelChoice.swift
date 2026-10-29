import Foundation

/// Built-in on-device speech models shown in Settings.
/// Fast / Balanced stay on WhisperKit; Highest is NVIDIA Parakeet via FluidAudio.
/// Bars are relative to this list. Size follows the published download.
struct SpeechModelChoice: Identifiable, Equatable {
    var variant: String
    var title: String
    var detail: String
    var megabytes: Int
    /// Larger means faster on this list.
    var speed: Double
    /// Larger means more accurate on this list.
    var quality: Double
    var isDefault: Bool
    var backend: OnDeviceSpeechBackend

    var id: String { variant }

    /// Share of the largest download in the list.
    var size: Double {
        Double(megabytes) / Double(Self.largestDownload)
    }

    /// Parakeet (FluidAudio) needs Apple Silicon; WhisperKit stays available everywhere.
    var isSupportedOnThisMac: Bool {
        switch backend {
        case .whisperKit: return true
        case .fluidAudio: return AppleSilicon.isCurrent
        }
    }

    static let defaultsKey = "speech.model"

    /// Previous Highest WhisperKit variant. Migrated to Parakeet on load.
    static let legacyHighestVariant = "large-v3_turbo"

    /// FluidAudio / Hugging Face English Parakeet TDT 0.6B v2 Core ML bundle.
    static let parakeetVariant = "parakeet-tdt-0.6b-v2"

    static let all: [SpeechModelChoice] = [
        SpeechModelChoice(
            variant: "tiny.en",
            title: "Fast",
            detail: "The smallest English WhisperKit model. Best when you want the words quickly.",
            megabytes: 153,
            speed: 0.92,
            quality: 0.34,
            isDefault: false,
            backend: .whisperKit
        ),
        SpeechModelChoice(
            variant: "small.en_217MB",
            title: "Balanced",
            detail: "The default. English WhisperKit, small enough to keep loaded.",
            megabytes: 217,
            speed: 0.68,
            quality: 0.70,
            isDefault: true,
            backend: .whisperKit
        ),
        SpeechModelChoice(
            variant: parakeetVariant,
            title: "Highest",
            detail: "NVIDIA Parakeet TDT 0.6B v2 (English) via FluidAudio. Best accuracy of these three, and faster than the old turbo.",
            megabytes: 443,
            speed: 0.85,
            quality: 0.96,
            isDefault: false,
            backend: .fluidAudio
        ),
    ]

    static var recommended: SpeechModelChoice {
        all.first { $0.isDefault } ?? all[0]
    }

    static var parakeet: SpeechModelChoice {
        all.first { $0.variant == parakeetVariant } ?? recommended
    }

    /// Maps legacy / unknown stored values onto a choice.
    /// `large-v3_turbo` → Parakeet. Unsupported backends (Intel + Parakeet) → recommended.
    static func stored(_ raw: String?) -> SpeechModelChoice {
        let key = migratedVariant(raw)
        guard let choice = all.first(where: { $0.variant == key }) else {
            return recommended
        }
        guard choice.isSupportedOnThisMac else {
            return recommended
        }
        return choice
    }

    /// Pure migration without availability checks (for tests).
    static func migratedVariant(_ raw: String?) -> String? {
        switch raw {
        case legacyHighestVariant:
            return parakeetVariant
        default:
            return raw
        }
    }

    private static var largestDownload: Int {
        all.map(\.megabytes).max() ?? 1
    }
}
