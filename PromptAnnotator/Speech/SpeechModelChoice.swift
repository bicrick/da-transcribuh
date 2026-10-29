import Foundation

/// Built-in on-device speech models shown in Settings as a stats list.
/// Stats come from Open ASR leaderboard / model cards — omit a field when unknown.
/// Bars are relative to models in this list that publish that metric.
struct SpeechModelChoice: Identifiable, Equatable {
    var variant: String
    var title: String
    var detail: String
    /// Download size in MB (published / measured).
    var megabytes: Int
    /// Open ASR leaderboard English short-form average WER (lower is better). Nil if unknown.
    var openASRAvgWER: Double?
    /// Open ASR leaderboard RTFx (higher is better). Nil if unknown.
    var openASRRTFx: Double?
    /// Relative speed bar 0…1 when RTFx is known; nil otherwise.
    var speed: Double?
    /// Relative quality bar 0…1 derived from avg WER when known; nil otherwise.
    var quality: Double?
    var languages: String
    /// Compact flag chips shown on the model row (emoji). Overflow goes in `languageOverflowCount`.
    var languageFlagEmojis: [String]
    /// Names matching `languageFlagEmojis` (same order) for tooltips.
    var languageFlagNames: [String]
    /// Extra languages beyond the preview chips (shown as "+N").
    var languageOverflowCount: Int
    /// Full language list for hover help.
    var languageTooltip: String
    /// Short line under the flags: English-only vs auto-detect.
    var languageBehavior: String
    /// True only for multilingual WhisperKit — future #66 language picker should gate on this.
    var benefitsFromLanguagePicker: Bool
    var license: String
    var appleSiliconOnly: Bool
    var backend: OnDeviceSpeechBackend
    /// Hugging Face repo for attribution / docs (optional).
    var huggingFaceRepo: String?

    var id: String { variant }

    /// Share of the largest download in the list.
    var size: Double {
        Double(megabytes) / Double(Self.largestDownload)
    }

    var supportsLiveCaptions: Bool {
        backend.supportsLiveCaptions
    }

    /// Parakeet (FluidAudio) needs Apple Silicon; WhisperKit stays available everywhere.
    var isSupportedOnThisMac: Bool {
        if appleSiliconOnly { return AppleSilicon.isCurrent }
        switch backend {
        case .whisperKit: return true
        case .fluidAudio: return AppleSilicon.isCurrent
        }
    }

    /// Default badge for this Mac: Parakeet v2 on Apple Silicon, small.en on Intel.
    var isDefaultOnThisMac: Bool {
        variant == Self.recommended.variant
    }

    static let defaultsKey = "speech.model"

    /// Previous Highest WhisperKit variant. Remapped to Parakeet by #68 for anyone
    /// who launched that build. Kept as a selectable list entry again — see `migratedVariant`.
    static let legacyHighestVariant = "large-v3_turbo"

    /// FluidAudio / Hugging Face English Parakeet TDT 0.6B v2 Core ML bundle (default on Apple Silicon).
    static let parakeetVariant = "parakeet-tdt-0.6b-v2"
    static let parakeetV3Variant = "parakeet-tdt-0.6b-v3"
    static let parakeetUltraVariant = "parakeet-ultra"
    static let whisperFallbackVariant = "small.en_217MB"

    /// Catalog order: default Parakeet first, then other Parakeet, then WhisperKit by size.
    static let all: [SpeechModelChoice] = {
        let rows: [SpeechModelChoice] = [
            SpeechModelChoice(
                variant: parakeetVariant,
                title: "Parakeet TDT 0.6B v2",
                detail: "English. Best accuracy/speed among these for dictation. Batch final transcript (no live captions).",
                megabytes: 443,
                openASRAvgWER: 6.05,
                openASRRTFx: 3386,
                speed: nil,
                quality: nil,
                languages: "English",
                languageFlagEmojis: ["🇺🇸"],
                languageFlagNames: ["English"],
                languageOverflowCount: 0,
                languageTooltip: "English",
                languageBehavior: "English only",
                benefitsFromLanguagePicker: false,
                license: "CC-BY-4.0",
                appleSiliconOnly: true,
                backend: .fluidAudio,
                huggingFaceRepo: "FluidInference/parakeet-tdt-0.6b-v2-coreml"
            ),
            SpeechModelChoice(
                variant: parakeetV3Variant,
                title: "Parakeet TDT 0.6B v3",
                detail: "25 European languages; auto-detects language. Slightly higher English WER than v2. Batch final transcript.",
                megabytes: 467,
                openASRAvgWER: 6.32,
                openASRRTFx: 3333,
                speed: nil,
                quality: nil,
                languages: "25 European",
                languageFlagEmojis: ["🇬🇧", "🇪🇸", "🇫🇷", "🇩🇪", "🇮🇹", "🇵🇱"],
                languageFlagNames: ["English", "Spanish", "French", "German", "Italian", "Polish"],
                languageOverflowCount: 19,
                languageTooltip: "Bulgarian, Croatian, Czech, Danish, Dutch, English, Estonian, Finnish, French, German, Greek, Hungarian, Italian, Latvian, Lithuanian, Maltese, Polish, Portuguese, Romanian, Slovak, Slovenian, Spanish, Swedish, Russian, Ukrainian (25). Auto-detects language.",
                languageBehavior: "Auto-detects language",
                benefitsFromLanguagePicker: false,
                license: "CC-BY-4.0",
                appleSiliconOnly: true,
                backend: .fluidAudio,
                huggingFaceRepo: "FluidInference/parakeet-tdt-0.6b-v3-coreml"
            ),
            SpeechModelChoice(
                variant: parakeetUltraVariant,
                title: "Parakeet Ultra",
                detail: "Full-precision post-training of v3 (FluidAudio). Same 25 languages; auto-detects. Larger download.",
                megabytes: 600,
                openASRAvgWER: nil,
                openASRRTFx: nil,
                speed: nil,
                quality: nil,
                languages: "25 European",
                languageFlagEmojis: ["🇬🇧", "🇪🇸", "🇫🇷", "🇩🇪", "🇮🇹", "🇵🇱"],
                languageFlagNames: ["English", "Spanish", "French", "German", "Italian", "Polish"],
                languageOverflowCount: 19,
                languageTooltip: "Bulgarian, Croatian, Czech, Danish, Dutch, English, Estonian, Finnish, French, German, Greek, Hungarian, Italian, Latvian, Lithuanian, Maltese, Polish, Portuguese, Romanian, Slovak, Slovenian, Spanish, Swedish, Russian, Ukrainian (25). Auto-detects language.",
                languageBehavior: "Auto-detects language",
                benefitsFromLanguagePicker: false,
                license: "CC-BY-4.0",
                appleSiliconOnly: true,
                backend: .fluidAudio,
                huggingFaceRepo: "FluidInference/parakeet-ultra-coreml"
            ),
            SpeechModelChoice(
                variant: "tiny.en",
                title: "Whisper tiny.en",
                detail: "Smallest English WhisperKit model. Fastest download; weakest accuracy of the list.",
                megabytes: 153,
                openASRAvgWER: 12.81,
                openASRRTFx: 348,
                speed: nil,
                quality: nil,
                languages: "English",
                languageFlagEmojis: ["🇺🇸"],
                languageFlagNames: ["English"],
                languageOverflowCount: 0,
                languageTooltip: "English",
                languageBehavior: "English only",
                benefitsFromLanguagePicker: false,
                license: "MIT",
                appleSiliconOnly: false,
                backend: .whisperKit,
                huggingFaceRepo: "argmaxinc/whisperkit-coreml"
            ),
            SpeechModelChoice(
                variant: "base.en",
                title: "Whisper base.en",
                detail: "Small English WhisperKit step up from tiny. Live captions supported.",
                megabytes: 147,
                openASRAvgWER: nil,
                openASRRTFx: nil,
                speed: nil,
                quality: nil,
                languages: "English",
                languageFlagEmojis: ["🇺🇸"],
                languageFlagNames: ["English"],
                languageOverflowCount: 0,
                languageTooltip: "English",
                languageBehavior: "English only",
                benefitsFromLanguagePicker: false,
                license: "MIT",
                appleSiliconOnly: false,
                backend: .whisperKit,
                huggingFaceRepo: "argmaxinc/whisperkit-coreml"
            ),
            SpeechModelChoice(
                variant: whisperFallbackVariant,
                title: "Whisper small.en",
                detail: "Former default. Solid English WhisperKit; default on Intel Macs.",
                megabytes: 217,
                openASRAvgWER: 8.59,
                openASRRTFx: 269,
                speed: nil,
                quality: nil,
                languages: "English",
                languageFlagEmojis: ["🇺🇸"],
                languageFlagNames: ["English"],
                languageOverflowCount: 0,
                languageTooltip: "English",
                languageBehavior: "English only",
                benefitsFromLanguagePicker: false,
                license: "MIT",
                appleSiliconOnly: false,
                backend: .whisperKit,
                huggingFaceRepo: "argmaxinc/whisperkit-coreml"
            ),
            SpeechModelChoice(
                variant: legacyHighestVariant,
                title: "Whisper large-v3 turbo",
                detail: "Multilingual WhisperKit (~99 languages); auto-detects. Heavier download; live captions supported.",
                megabytes: 954,
                openASRAvgWER: 7.83,
                openASRRTFx: 200,
                speed: nil,
                quality: nil,
                languages: "Multilingual",
                languageFlagEmojis: ["🇺🇸", "🇪🇸", "🇫🇷", "🇩🇪", "🇯🇵", "🇨🇳"],
                languageFlagNames: ["English", "Spanish", "French", "German", "Japanese", "Chinese"],
                languageOverflowCount: 93,
                languageTooltip: "Whisper multilingual (~99 languages). Auto-detects by default; an explicit language picker (#66) should only apply to this family.",
                languageBehavior: "Auto-detects language",
                benefitsFromLanguagePicker: true,
                license: "MIT",
                appleSiliconOnly: false,
                backend: .whisperKit,
                huggingFaceRepo: "argmaxinc/whisperkit-coreml"
            ),
        ]
        return rows.map { row in
            var copy = row
            copy.speed = Self.speedBar(rtfx: row.openASRRTFx, among: rows)
            copy.quality = Self.qualityBar(wer: row.openASRAvgWER, among: rows)
            return copy
        }
    }()

    /// Parakeet v2 on Apple Silicon; Whisper small.en on Intel.
    static var recommended: SpeechModelChoice {
        if AppleSilicon.isCurrent {
            return all.first { $0.variant == parakeetVariant } ?? all[0]
        }
        return all.first { $0.variant == whisperFallbackVariant } ?? all[0]
    }

    static var parakeet: SpeechModelChoice {
        all.first { $0.variant == parakeetVariant } ?? recommended
    }

    /// Always a WhisperKit variant — used when Parakeet/custom fails and we must decode on-device once.
    static var whisperFallback: SpeechModelChoice {
        all.first { $0.variant == whisperFallbackVariant } ?? all.first { $0.backend == .whisperKit }!
    }

    /// Maps unknown stored values onto a choice. Unsupported backends (Intel + Parakeet) → recommended.
    /// Does **not** remap `large-v3_turbo` — #68 already migrated those users to Parakeet; turbo is selectable again.
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
    /// Identity for known variants. Unknown / nil left as-is for `stored` to resolve.
    static func migratedVariant(_ raw: String?) -> String? {
        raw
    }

    static func choice(for variant: String) -> SpeechModelChoice? {
        all.first { $0.variant == variant }
    }

    private static var largestDownload: Int {
        all.map(\.megabytes).max() ?? 1
    }

    /// Higher RTFx → fuller bar. Relative to the max RTFx in the catalog.
    private static func speedBar(rtfx: Double?, among rows: [SpeechModelChoice]) -> Double? {
        guard let rtfx else { return nil }
        let maxRTFx = rows.compactMap(\.openASRRTFx).max() ?? rtfx
        guard maxRTFx > 0 else { return nil }
        return min(1, max(0.08, rtfx / maxRTFx))
    }

    /// Lower WER → fuller bar. Maps the catalog’s WER span onto ~0.2…1.
    private static func qualityBar(wer: Double?, among rows: [SpeechModelChoice]) -> Double? {
        guard let wer else { return nil }
        let wers = rows.compactMap(\.openASRAvgWER)
        guard let best = wers.min(), let worst = wers.max(), worst > best else {
            return 0.85
        }
        let t = (wer - best) / (worst - best)
        return min(1, max(0.2, 1 - t))
    }
}
