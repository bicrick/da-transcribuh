import XCTest
@testable import PromptAnnotator

final class SpeechModelChoiceTests: XCTestCase {
    func testBalancedModelIsTheDefault() {
        XCTAssertEqual(SpeechModelChoice.recommended.variant, "small.en_217MB")
        XCTAssertEqual(SpeechModelChoice.stored(nil).variant, "small.en_217MB")
        XCTAssertEqual(SpeechModelChoice.stored("not-a-model").variant, "small.en_217MB")
        XCTAssertEqual(
            SpeechModelChoice.all.map(\.variant),
            ["tiny.en", "small.en_217MB", SpeechModelChoice.parakeetVariant]
        )
    }

    func testHighestIsParakeetNotWhisperTurbo() {
        let highest = SpeechModelChoice.all[2]
        XCTAssertEqual(highest.title, "Highest")
        XCTAssertEqual(highest.variant, "parakeet-tdt-0.6b-v2")
        XCTAssertEqual(highest.backend, .fluidAudio)
        XCTAssertEqual(highest.megabytes, 443)
        XCTAssertFalse(SpeechModelChoice.all.contains { $0.variant == "large-v3_turbo" })
    }

    func testLegacyTurboMigratesToParakeetVariant() {
        XCTAssertEqual(
            SpeechModelChoice.migratedVariant("large-v3_turbo"),
            SpeechModelChoice.parakeetVariant
        )
        XCTAssertEqual(SpeechModelChoice.migratedVariant("tiny.en"), "tiny.en")
        XCTAssertNil(SpeechModelChoice.migratedVariant(nil))
    }

    func testStoredMigratesTurboWhenParakeetIsSupported() {
        // On Apple Silicon, turbo → Parakeet. On Intel, availability falls back to Balanced.
        let resolved = SpeechModelChoice.stored("large-v3_turbo")
        if AppleSilicon.isCurrent {
            XCTAssertEqual(resolved.variant, SpeechModelChoice.parakeetVariant)
            XCTAssertEqual(resolved.backend, .fluidAudio)
        } else {
            XCTAssertEqual(resolved.variant, "small.en_217MB")
        }
    }

    func testBarsStayInRangeAndOrderTheThreeModels() {
        let models = SpeechModelChoice.all
        for model in models {
            XCTAssertGreaterThan(model.size, 0)
            XCTAssertLessThanOrEqual(model.size, 1)
            XCTAssertGreaterThan(model.speed, 0)
            XCTAssertLessThanOrEqual(model.speed, 1)
            XCTAssertGreaterThan(model.quality, 0)
            XCTAssertLessThanOrEqual(model.quality, 1)
        }
        let tiny = models[0]
        let balanced = models[1]
        let highest = models[2]
        XCTAssertLessThan(tiny.megabytes, balanced.megabytes)
        XCTAssertLessThan(balanced.megabytes, highest.megabytes)
        XCTAssertGreaterThan(tiny.speed, balanced.speed)
        // Parakeet is both higher quality and faster than Balanced (unlike old turbo).
        XCTAssertGreaterThan(highest.speed, balanced.speed)
        XCTAssertLessThan(tiny.quality, balanced.quality)
        XCTAssertLessThan(balanced.quality, highest.quality)
        XCTAssertEqual(highest.size, 1, accuracy: 0.001)
    }

    func testWhisperBackendsSupportLiveCaptionsParakeetDoesNot() {
        XCTAssertTrue(OnDeviceSpeechBackend.whisperKit.supportsLiveCaptions)
        XCTAssertFalse(OnDeviceSpeechBackend.fluidAudio.supportsLiveCaptions)
        XCTAssertEqual(SpeechModelChoice.all[0].backend, .whisperKit)
        XCTAssertEqual(SpeechModelChoice.all[1].backend, .whisperKit)
        XCTAssertEqual(SpeechModelChoice.all[2].backend, .fluidAudio)
    }

    @MainActor
    func testSpeechModelSettingDefaultsToTheBalancedModel() {
        let name = "PromptAnnotatorTests.speechModel.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        let settings = AppSettings(defaults: defaults)
        XCTAssertEqual(settings.speechModel, "small.en_217MB")
        settings.setSpeechModel("tiny.en")
        XCTAssertEqual(AppSettings(defaults: defaults).speechModel, "tiny.en")
        settings.setSpeechModel("nope")
        XCTAssertEqual(AppSettings(defaults: defaults).speechModel, "small.en_217MB")
        defaults.removePersistentDomain(forName: name)
    }

    @MainActor
    func testSpeechModelSettingMigratesLegacyTurbo() {
        let name = "PromptAnnotatorTests.speechModel.turbo.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        defaults.set("large-v3_turbo", forKey: SpeechModelChoice.defaultsKey)
        let settings = AppSettings(defaults: defaults)
        if AppleSilicon.isCurrent {
            XCTAssertEqual(settings.speechModel, SpeechModelChoice.parakeetVariant)
            XCTAssertEqual(
                defaults.string(forKey: SpeechModelChoice.defaultsKey),
                SpeechModelChoice.parakeetVariant
            )
        } else {
            XCTAssertEqual(settings.speechModel, "small.en_217MB")
        }
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
