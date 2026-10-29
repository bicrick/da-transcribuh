import XCTest
@testable import PromptAnnotator

final class SpeechModelChoiceTests: XCTestCase {
    func testCatalogIncludesParakeetAndWhisperVariants() {
        let variants = SpeechModelChoice.all.map(\.variant)
        XCTAssertEqual(
            variants,
            [
                SpeechModelChoice.parakeetVariant,
                SpeechModelChoice.parakeetV3Variant,
                SpeechModelChoice.parakeetUltraVariant,
                "tiny.en",
                "base.en",
                "small.en_217MB",
                "large-v3_turbo",
            ]
        )
        XCTAssertEqual(SpeechModelChoice.all.count, 7)
    }

    func testDefaultIsParakeetOnAppleSiliconElseSmall() {
        let recommended = SpeechModelChoice.recommended.variant
        if AppleSilicon.isCurrent {
            XCTAssertEqual(recommended, SpeechModelChoice.parakeetVariant)
            XCTAssertEqual(SpeechModelChoice.stored(nil).variant, SpeechModelChoice.parakeetVariant)
            XCTAssertEqual(SpeechModelChoice.stored("not-a-model").variant, SpeechModelChoice.parakeetVariant)
        } else {
            XCTAssertEqual(recommended, "small.en_217MB")
            XCTAssertEqual(SpeechModelChoice.stored(nil).variant, "small.en_217MB")
        }
        XCTAssertTrue(SpeechModelChoice.recommended.isDefaultOnThisMac)
    }

    func testExistingSmallEnIsLeftAlone() {
        // Cannot distinguish explicit pick from old default — leave stored small.en alone.
        XCTAssertEqual(SpeechModelChoice.stored("small.en_217MB").variant, "small.en_217MB")
        XCTAssertEqual(SpeechModelChoice.migratedVariant("small.en_217MB"), "small.en_217MB")
    }

    func testLargeV3TurboIsSelectableAgain() {
        let turbo = SpeechModelChoice.all.first { $0.variant == "large-v3_turbo" }
        XCTAssertNotNil(turbo)
        XCTAssertEqual(turbo?.backend, .whisperKit)
        XCTAssertEqual(turbo?.megabytes, 954)
        XCTAssertEqual(turbo?.openASRAvgWER, 7.83)
        // No remapping — #68 already migrated users who launched that build.
        XCTAssertEqual(SpeechModelChoice.migratedVariant("large-v3_turbo"), "large-v3_turbo")
        XCTAssertEqual(SpeechModelChoice.stored("large-v3_turbo").variant, "large-v3_turbo")
    }

    func testParakeetRowsCarryFluidAudioStats() {
        let v2 = SpeechModelChoice.parakeet
        XCTAssertEqual(v2.backend, .fluidAudio)
        XCTAssertEqual(v2.megabytes, 443)
        XCTAssertEqual(v2.openASRAvgWER, 6.05)
        XCTAssertEqual(v2.openASRRTFx, 3386)
        XCTAssertTrue(v2.appleSiliconOnly)
        XCTAssertFalse(v2.supportsLiveCaptions)
        XCTAssertEqual(v2.license, "CC-BY-4.0")

        let v3 = try XCTUnwrap(SpeechModelChoice.choice(for: SpeechModelChoice.parakeetV3Variant))
        XCTAssertEqual(v3.openASRAvgWER, 6.32)
        XCTAssertEqual(v3.languages, "25 European")

        let ultra = try XCTUnwrap(SpeechModelChoice.choice(for: SpeechModelChoice.parakeetUltraVariant))
        XCTAssertNil(ultra.openASRAvgWER) // not published separately on Open ASR short-form
        XCTAssertEqual(ultra.megabytes, 600)
    }

    func testWhisperRowsAndOmittedUnknownStats() {
        let tiny = try XCTUnwrap(SpeechModelChoice.choice(for: "tiny.en"))
        XCTAssertEqual(tiny.openASRAvgWER, 12.81)
        XCTAssertTrue(tiny.supportsLiveCaptions)

        let base = try XCTUnwrap(SpeechModelChoice.choice(for: "base.en"))
        XCTAssertNil(base.openASRAvgWER)
        XCTAssertNil(base.speed)
        XCTAssertNil(base.quality)
        XCTAssertEqual(base.megabytes, 147)

        let small = try XCTUnwrap(SpeechModelChoice.choice(for: "small.en_217MB"))
        XCTAssertEqual(small.openASRAvgWER, 8.59)
    }

    func testBarsStayInRangeWhenPresent() {
        for model in SpeechModelChoice.all {
            XCTAssertGreaterThan(model.size, 0)
            XCTAssertLessThanOrEqual(model.size, 1)
            if let speed = model.speed {
                XCTAssertGreaterThan(speed, 0)
                XCTAssertLessThanOrEqual(speed, 1)
            }
            if let quality = model.quality {
                XCTAssertGreaterThan(quality, 0)
                XCTAssertLessThanOrEqual(quality, 1)
            }
        }
        let v2 = SpeechModelChoice.parakeet
        let tiny = try XCTUnwrap(SpeechModelChoice.choice(for: "tiny.en"))
        XCTAssertNotNil(v2.quality)
        XCTAssertNotNil(tiny.quality)
        XCTAssertGreaterThan(v2.quality!, tiny.quality!)
        XCTAssertGreaterThan(v2.speed!, tiny.speed!)
    }

    func testUnsupportedParakeetFallsBackOnIntel() {
        // On Intel, selecting a Parakeet variant resolves to recommended (small.en).
        // On Apple Silicon, Parakeet stays.
        let resolved = SpeechModelChoice.stored(SpeechModelChoice.parakeetVariant)
        if AppleSilicon.isCurrent {
            XCTAssertEqual(resolved.variant, SpeechModelChoice.parakeetVariant)
        } else {
            XCTAssertEqual(resolved.variant, "small.en_217MB")
        }
    }

    func testWhisperFallbackIsAlwaysSmallEn() {
        XCTAssertEqual(SpeechModelChoice.whisperFallback.variant, "small.en_217MB")
        XCTAssertEqual(SpeechModelChoice.whisperFallback.backend, .whisperKit)
    }

    @MainActor
    func testSpeechModelSettingDefaultsToRecommended() {
        let name = "PromptAnnotatorTests.speechModel.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        let settings = AppSettings(defaults: defaults)
        XCTAssertEqual(settings.speechModel, SpeechModelChoice.recommended.variant)
        settings.setSpeechModel("tiny.en")
        XCTAssertEqual(AppSettings(defaults: defaults).speechModel, "tiny.en")
        settings.setSpeechModel("nope")
        XCTAssertEqual(AppSettings(defaults: defaults).speechModel, SpeechModelChoice.recommended.variant)
        defaults.removePersistentDomain(forName: name)
    }

    @MainActor
    func testSpeechModelSettingKeepsLargeV3Turbo() {
        let name = "PromptAnnotatorTests.speechModel.turbo.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        defaults.set("large-v3_turbo", forKey: SpeechModelChoice.defaultsKey)
        let settings = AppSettings(defaults: defaults)
        XCTAssertEqual(settings.speechModel, "large-v3_turbo")
        defaults.removePersistentDomain(forName: name)
    }

    @MainActor
    func testFallBackToDefaultWhisperModelAlwaysUsesSmallEn() {
        let name = "PromptAnnotatorTests.speechModel.fallback.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        let settings = AppSettings(defaults: defaults)
        if AppleSilicon.isCurrent {
            settings.setSpeechModel(SpeechModelChoice.parakeetVariant)
        } else {
            settings.setSpeechModel("tiny.en")
        }
        settings.fallBackToDefaultWhisperModel()
        XCTAssertEqual(settings.speechModel, "small.en_217MB")
        defaults.removePersistentDomain(forName: name)
    }

    @MainActor
    func testLiveCaptionsOffForParakeetWhenSupported() {
        guard AppleSilicon.isCurrent else { return }
        let name = "PromptAnnotatorTests.liveCaptions.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        let settings = AppSettings(defaults: defaults)
        settings.setSpeechEngine(.whisperKit)
        settings.setSpeechModel("tiny.en")
        XCTAssertTrue(settings.liveCaptionsEnabled)
        settings.setSpeechModel(SpeechModelChoice.parakeetVariant)
        XCTAssertFalse(settings.liveCaptionsEnabled)
        defaults.removePersistentDomain(forName: name)
    }
}
