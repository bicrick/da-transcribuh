import Foundation

/// Whisper decode language + onboarding language → model recommendation.
/// Persisted under `speech.language` (same key as PR #66). English-only (`.en`)
/// WhisperKit weights ignore this; Parakeet v3 / turbo auto-detect when left on
/// `auto`. The onboarding pick mainly steers which model we recommend.
enum TranscriptionLanguage {
    static let defaultsKey = "speech.language"
    static let auto = "auto"
    static let english = "en"

    struct Choice: Identifiable, Equatable, Hashable {
        var id: String { code }
        let code: String
        let name: String
        let flag: String
    }

    /// Onboarding / Settings list. English first, then common European (Parakeet v3),
    /// then languages that need Whisper turbo, then "Other".
    static let onboardingChoices: [Choice] = [
        Choice(code: "en", name: "English", flag: "🇺🇸"),
        Choice(code: "es", name: "Spanish", flag: "🇪🇸"),
        Choice(code: "fr", name: "French", flag: "🇫🇷"),
        Choice(code: "de", name: "German", flag: "🇩🇪"),
        Choice(code: "it", name: "Italian", flag: "🇮🇹"),
        Choice(code: "pt", name: "Portuguese", flag: "🇵🇹"),
        Choice(code: "nl", name: "Dutch", flag: "🇳🇱"),
        Choice(code: "pl", name: "Polish", flag: "🇵🇱"),
        Choice(code: "ru", name: "Russian", flag: "🇷🇺"),
        Choice(code: "uk", name: "Ukrainian", flag: "🇺🇦"),
        Choice(code: "sv", name: "Swedish", flag: "🇸🇪"),
        Choice(code: "da", name: "Danish", flag: "🇩🇰"),
        Choice(code: "fi", name: "Finnish", flag: "🇫🇮"),
        Choice(code: "cs", name: "Czech", flag: "🇨🇿"),
        Choice(code: "sk", name: "Slovak", flag: "🇸🇰"),
        Choice(code: "ro", name: "Romanian", flag: "🇷🇴"),
        Choice(code: "hu", name: "Hungarian", flag: "🇭🇺"),
        Choice(code: "el", name: "Greek", flag: "🇬🇷"),
        Choice(code: "bg", name: "Bulgarian", flag: "🇧🇬"),
        Choice(code: "hr", name: "Croatian", flag: "🇭🇷"),
        Choice(code: "sl", name: "Slovenian", flag: "🇸🇮"),
        Choice(code: "et", name: "Estonian", flag: "🇪🇪"),
        Choice(code: "lv", name: "Latvian", flag: "🇱🇻"),
        Choice(code: "lt", name: "Lithuanian", flag: "🇱🇹"),
        Choice(code: "mt", name: "Maltese", flag: "🇲🇹"),
        Choice(code: "ja", name: "Japanese", flag: "🇯🇵"),
        Choice(code: "ko", name: "Korean", flag: "🇰🇷"),
        Choice(code: "zh", name: "Chinese", flag: "🇨🇳"),
        Choice(code: "hi", name: "Hindi", flag: "🇮🇳"),
        Choice(code: auto, name: "Other / many languages", flag: "🌐"),
    ]

    /// Compact picker rows for Settings (code, display name) — same order as onboarding.
    static var choices: [(String, String)] {
        onboardingChoices.map { ($0.code, $0.name) }
    }

    /// Parakeet TDT 0.6B v3 European set, excluding English (English prefers v2).
    static let parakeetV3LanguageCodes: Set<String> = [
        "bg", "hr", "cs", "da", "nl", "et", "fi", "fr", "de", "el", "hu", "it",
        "lv", "lt", "mt", "pl", "pt", "ro", "sk", "sl", "es", "sv", "ru", "uk",
    ]

    /// Empty / unknown → English, so existing installs decode as before.
    static func stored(_ raw: String?) -> String {
        guard let raw, onboardingChoices.contains(where: { $0.code == raw }) else {
            return english
        }
        return raw
    }

    static func choice(for code: String) -> Choice? {
        onboardingChoices.first { $0.code == stored(code) }
    }

    /// Model variant for this language on the given Mac.
    /// English → Parakeet v2 (Apple Silicon) / small.en (Intel);
    /// Parakeet-v3 European → Parakeet v3 (Apple Silicon) / turbo (Intel);
    /// everything else (incl. auto) → Whisper large-v3 turbo.
    static func recommendedVariant(
        for code: String,
        appleSilicon: Bool = AppleSilicon.isCurrent
    ) -> String {
        let resolved = stored(code)
        if resolved == english {
            return appleSilicon
                ? SpeechModelChoice.parakeetVariant
                : SpeechModelChoice.whisperFallbackVariant
        }
        if parakeetV3LanguageCodes.contains(resolved) {
            return appleSilicon
                ? SpeechModelChoice.parakeetV3Variant
                : SpeechModelChoice.legacyHighestVariant
        }
        return SpeechModelChoice.legacyHighestVariant
    }

    static func recommendedChoice(
        for code: String,
        appleSilicon: Bool = AppleSilicon.isCurrent
    ) -> SpeechModelChoice {
        let variant = recommendedVariant(for: code, appleSilicon: appleSilicon)
        return SpeechModelChoice.choice(for: variant) ?? SpeechModelChoice.recommended
    }

    /// Short reason shown under the recommended model on the language step.
    static func recommendationReason(
        for code: String,
        appleSilicon: Bool = AppleSilicon.isCurrent
    ) -> String {
        let resolved = stored(code)
        if resolved == english {
            if appleSilicon {
                return "English dictation. Parakeet v2 is the default — fast and accurate on Apple Silicon."
            }
            return "English dictation. Whisper small.en is the default on Intel Macs."
        }
        if parakeetV3LanguageCodes.contains(resolved) {
            let name = choice(for: resolved)?.name ?? resolved
            if appleSilicon {
                return "\(name) is one of Parakeet v3's 25 European languages. It auto-detects which one you're speaking."
            }
            return "\(name) needs a multilingual model. Parakeet needs Apple Silicon, so Whisper large-v3 turbo is the pick on this Mac."
        }
        if resolved == auto {
            return "Whisper large-v3 turbo covers ~99 languages and auto-detects. Heavier download."
        }
        let name = choice(for: resolved)?.name ?? resolved
        return "\(name) is outside Parakeet's coverage. Whisper large-v3 turbo (~99 languages) auto-detects."
    }
}
