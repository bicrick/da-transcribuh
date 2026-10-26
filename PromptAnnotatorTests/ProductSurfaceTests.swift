import Carbon.HIToolbox
import XCTest
@testable import PromptAnnotator

final class ProductSurfaceTests: XCTestCase {
    func testBetaLabelCarriesTheMarketingVersionAndBuild() {
        XCTAssertEqual(AppVersion.channel, "beta")
        XCTAssertEqual(AppVersion.marketing, "0.9.7")
        XCTAssertEqual(AppVersion.build, "9")
        XCTAssertEqual(AppVersion.label, "0.9.7 beta (9)")
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

    private func freshOnboardingDefaults() -> UserDefaults {
        UserDefaults(suiteName: "prompt-annotator.onboarding.\(UUID().uuidString)")!
    }

    /// Screen Recording makes macOS quit and reopen the app mid-setup. The
    /// relaunch has to land back on the step the user left, not on Welcome.
    func testOnboardingResumesTheSavedStepAfterARelaunch() {
        let defaults = freshOnboardingDefaults()
        XCTAssertNil(OnboardingStore.savedStep(defaults))
        XCTAssertEqual(OnboardingStore.resumeStep(defaults), .welcome)

        OnboardingStore.saveStep(.permissions, defaults)
        XCTAssertEqual(OnboardingStore.savedStep(defaults), .permissions)
        XCTAssertEqual(OnboardingStore.resumeStep(defaults), .permissions)
        XCTAssertFalse(OnboardingStore.isFinished(defaults), "a relaunch must not skip setup")

        OnboardingStore.saveStep(.model, defaults)
        XCTAssertEqual(OnboardingStore.resumeStep(defaults), .model, "the latest step wins")

        OnboardingStore.saveStep(.welcome, defaults)
        XCTAssertEqual(OnboardingStore.resumeStep(defaults), .welcome, "going Back is saved too")
    }

    func testFinishingOnboardingClearsTheSavedStep() {
        let defaults = freshOnboardingDefaults()
        OnboardingStore.saveStep(.permissions, defaults)
        OnboardingStore.finish(defaults)
        XCTAssertTrue(OnboardingStore.isFinished(defaults))
        XCTAssertNil(OnboardingStore.savedStep(defaults))
        XCTAssertEqual(OnboardingStore.resumeStep(defaults), .welcome)
    }

    /// "Show welcome" in Settings replays from the top and leaves nothing saved.
    func testReplayingWelcomeAfterSetupNeverSavesAStep() {
        let defaults = freshOnboardingDefaults()
        OnboardingStore.finish(defaults)
        OnboardingStore.saveStep(.practice, defaults)
        XCTAssertNil(OnboardingStore.savedStep(defaults))
        XCTAssertEqual(OnboardingStore.resumeStep(defaults), .welcome)
    }

    func testUnknownSavedStepFallsBackToWelcome() {
        let defaults = freshOnboardingDefaults()
        defaults.set(99, forKey: OnboardingStore.stepKey)
        XCTAssertNil(OnboardingStore.savedStep(defaults))
        XCTAssertEqual(OnboardingStore.resumeStep(defaults), .welcome)
        defaults.set("permissions", forKey: OnboardingStore.stepKey)
        XCTAssertEqual(OnboardingStore.resumeStep(defaults), .welcome)
    }

    /// The step is stored by raw value, so the order is part of the saved format.
    func testOnboardingStepRawValuesAreStable() {
        XCTAssertEqual(OnboardingStep.welcome.rawValue, 0)
        XCTAssertEqual(OnboardingStep.permissions.rawValue, 1)
        XCTAssertEqual(OnboardingStep.ready.rawValue, OnboardingStep.allCases.count - 1)
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
