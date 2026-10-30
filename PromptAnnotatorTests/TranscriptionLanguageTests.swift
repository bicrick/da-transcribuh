import XCTest
@testable import PromptAnnotator

final class TranscriptionLanguageTests: XCTestCase {
    func testOnboardingChoicesCoverParakeetV3AndTurboLanguages() {
        let codes = Set(TranscriptionLanguage.onboardingChoices.map(\.code))
        XCTAssertTrue(codes.contains("en"))
        XCTAssertTrue(codes.contains(TranscriptionLanguage.auto))
        for code in TranscriptionLanguage.parakeetV3LanguageCodes {
            XCTAssertTrue(codes.contains(code), "missing Parakeet v3 language \(code)")
        }
        for code in ["ja", "ko", "zh", "hi"] {
            XCTAssertTrue(codes.contains(code))
        }
        // English is NOT in the v3 routing set — it prefers v2.
        XCTAssertFalse(TranscriptionLanguage.parakeetV3LanguageCodes.contains("en"))
        XCTAssertEqual(TranscriptionLanguage.parakeetV3LanguageCodes.count, 24)
    }

    func testStoredFallsBackToEnglish() {
        XCTAssertEqual(TranscriptionLanguage.stored(nil), "en")
        XCTAssertEqual(TranscriptionLanguage.stored(""), "en")
        XCTAssertEqual(TranscriptionLanguage.stored("nope"), "en")
        XCTAssertEqual(TranscriptionLanguage.stored("es"), "es")
        XCTAssertEqual(TranscriptionLanguage.stored("auto"), "auto")
    }

    func testEnglishRecommendsParakeetV2OnAppleSiliconElseSmall() {
        XCTAssertEqual(
            TranscriptionLanguage.recommendedVariant(for: "en", appleSilicon: true),
            SpeechModelChoice.parakeetVariant
        )
        XCTAssertEqual(
            TranscriptionLanguage.recommendedVariant(for: "en", appleSilicon: false),
            SpeechModelChoice.whisperFallbackVariant
        )
        // Unknown codes store as English.
        XCTAssertEqual(
            TranscriptionLanguage.recommendedVariant(for: "zz", appleSilicon: true),
            SpeechModelChoice.parakeetVariant
        )
    }

    func testEuropeanLanguagesRecommendParakeetV3OnAppleSiliconElseTurbo() {
        for code in ["es", "fr", "de", "pl", "uk", "nl"] {
            XCTAssertEqual(
                TranscriptionLanguage.recommendedVariant(for: code, appleSilicon: true),
                SpeechModelChoice.parakeetV3Variant,
                code
            )
            XCTAssertEqual(
                TranscriptionLanguage.recommendedVariant(for: code, appleSilicon: false),
                SpeechModelChoice.legacyHighestVariant,
                code
            )
        }
    }

    func testNonEuropeanAndAutoRecommendTurboEverywhere() {
        for code in ["ja", "ko", "zh", "hi", "auto"] {
            XCTAssertEqual(
                TranscriptionLanguage.recommendedVariant(for: code, appleSilicon: true),
                SpeechModelChoice.legacyHighestVariant,
                code
            )
            XCTAssertEqual(
                TranscriptionLanguage.recommendedVariant(for: code, appleSilicon: false),
                SpeechModelChoice.legacyHighestVariant,
                code
            )
        }
    }

    func testRecommendationReasonsMentionTheRightFamily() {
        let en = TranscriptionLanguage.recommendationReason(for: "en", appleSilicon: true)
        XCTAssertTrue(en.localizedCaseInsensitiveContains("parakeet v2"))
        let es = TranscriptionLanguage.recommendationReason(for: "es", appleSilicon: true)
        XCTAssertTrue(es.localizedCaseInsensitiveContains("parakeet v3"))
        let ja = TranscriptionLanguage.recommendationReason(for: "ja", appleSilicon: true)
        XCTAssertTrue(ja.localizedCaseInsensitiveContains("turbo"))
        let intelEU = TranscriptionLanguage.recommendationReason(for: "de", appleSilicon: false)
        XCTAssertTrue(intelEU.localizedCaseInsensitiveContains("turbo"))
    }

    func testFlagsAndNamesPresent() {
        for choice in TranscriptionLanguage.onboardingChoices {
            XCTAssertFalse(choice.flag.isEmpty, choice.code)
            XCTAssertFalse(choice.name.isEmpty, choice.code)
        }
        XCTAssertEqual(TranscriptionLanguage.choice(for: "fr")?.flag, "🇫🇷")
        XCTAssertEqual(TranscriptionLanguage.choices.count, TranscriptionLanguage.onboardingChoices.count)
    }

    @MainActor
    func testApplyLanguageRecommendationPersistsLanguageAndModel() {
        let name = "PromptAnnotatorTests.langRec.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        let settings = AppSettings(defaults: defaults)

        settings.applyLanguageRecommendation("es", appleSilicon: true)
        XCTAssertEqual(settings.transcriptionLanguage, "es")
        XCTAssertEqual(settings.speechModel, SpeechModelChoice.parakeetV3Variant)
        XCTAssertEqual(defaults.string(forKey: TranscriptionLanguage.defaultsKey), "es")
        XCTAssertEqual(defaults.string(forKey: SpeechModelChoice.defaultsKey), SpeechModelChoice.parakeetV3Variant)

        settings.applyLanguageRecommendation("en", appleSilicon: true)
        XCTAssertEqual(settings.transcriptionLanguage, "en")
        XCTAssertEqual(settings.speechModel, SpeechModelChoice.parakeetVariant)

        settings.applyLanguageRecommendation("ja", appleSilicon: true)
        XCTAssertEqual(settings.speechModel, "large-v3_turbo")

        settings.applyLanguageRecommendation("fr", appleSilicon: false)
        XCTAssertEqual(settings.transcriptionLanguage, "fr")
        XCTAssertEqual(settings.speechModel, "large-v3_turbo")

        defaults.removePersistentDomain(forName: name)
    }

    @MainActor
    func testTranscriptionLanguageDefaultsToEnglish() {
        let name = "PromptAnnotatorTests.langDefault.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        let settings = AppSettings(defaults: defaults)
        XCTAssertEqual(settings.transcriptionLanguage, "en")
        settings.setTranscriptionLanguage("de")
        XCTAssertEqual(AppSettings(defaults: defaults).transcriptionLanguage, "de")
        defaults.removePersistentDomain(forName: name)
    }
}
