import XCTest
@testable import PromptAnnotator

final class SpeechModelChoiceTests: XCTestCase {
    func testBalancedModelIsTheDefault() {
        XCTAssertEqual(SpeechModelChoice.recommended.variant, "small.en_217MB")
        XCTAssertEqual(SpeechModelChoice.stored(nil).variant, "small.en_217MB")
        XCTAssertEqual(SpeechModelChoice.stored("not-a-model").variant, "small.en_217MB")
        XCTAssertEqual(SpeechModelChoice.all.map(\.variant), ["tiny.en", "small.en_217MB", "large-v3_turbo"])
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
        XCTAssertGreaterThan(balanced.speed, highest.speed)
        XCTAssertLessThan(tiny.quality, balanced.quality)
        XCTAssertLessThan(balanced.quality, highest.quality)
        XCTAssertEqual(highest.size, 1, accuracy: 0.001)
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
}
