import Carbon.HIToolbox
import XCTest
@testable import PromptAnnotator

final class ProductSurfaceTests: XCTestCase {
    func testBetaLabelCarriesTheMarketingVersionAndBuild() {
        XCTAssertEqual(AppVersion.channel, "beta")
        XCTAssertEqual(AppVersion.marketing, "0.9.5")
        XCTAssertEqual(AppVersion.build, "7")
        XCTAssertEqual(AppVersion.label, "0.9.5 beta (7)")
        XCTAssertEqual(ReleaseCheck.currentVersion(), AppVersion.marketing)
    }

    func testOnboardingStaysOpenUntilItIsFinished() {
        let defaults = UserDefaults(suiteName: "prompt-annotator.onboarding.\(UUID().uuidString)")!
        XCTAssertFalse(OnboardingStore.isFinished(defaults))
        OnboardingStore.finish(defaults)
        XCTAssertTrue(OnboardingStore.isFinished(defaults))
        XCTAssertEqual(
            OnboardingStep.allCases.map(\.title),
            [
                "Welcome",
                "Permissions",
                "Keybinds",
                "Clipboard history",
                "Appearance",
                "Model",
                "Try a session",
                "Ready",
            ]
        )
    }

    func testSoundSetsAreDistinct() {
        let starts = SoundTheme.allCases.map { Earcon.wave(.start, theme: $0) }
        XCTAssertEqual(Set(starts).count, SoundTheme.allCases.count)
        XCTAssertLessThan(
            Earcon.samples(.tile, theme: .click).count,
            Earcon.samples(.start, theme: .deep).count
        )
        XCTAssertNotEqual(Earcon.samples(.stopSpoken, theme: .classic), Earcon.samples(.stopSilent, theme: .classic))
    }

    func testFunctionKeyShortcutHasAName() {
        let chord = HotkeyChord(keyCode: UInt32(kVK_F5), carbonModifiers: UInt32(controlKey))
        XCTAssertEqual(chord.display, "⌃F5")
        XCTAssertTrue(chord.canRegister)
        XCTAssertNil(chord.rejection)
    }
}
