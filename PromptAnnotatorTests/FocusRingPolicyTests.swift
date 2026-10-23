import XCTest

/// Patrick wants no focus rings at all. Each window root disables focus effects,
/// and the AppKit key-capture views report no ring. Keyboard navigation is untouched.
final class FocusRingPolicyTests: XCTestCase {
    private func source(_ path: String) throws -> String {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("PromptAnnotator").appendingPathComponent(path)
        guard let text = try? String(contentsOf: url, encoding: .utf8) else {
            throw XCTSkip("sources not readable from the test host")
        }
        return text
    }

    func testEveryWindowRootDisablesFocusEffects() throws {
        for path in [
            "Settings/SettingsWindow.swift",          // main window and its ⌘K palette
            "Clipboard/ClipboardHistoryView.swift",   // clipboard panel and preview
            "Onboarding/OnboardingFlow.swift",
            "PromptAnnotatorApp.swift",               // menu bar panel
            "Settings/Ink/DTScrollView.swift",        // nested hosting views
            "Chrome/RecordingIsland.swift",
            "Chrome/MarkupToolbar.swift",
        ] {
            XCTAssertTrue(try source(path).contains(".focusEffectDisabled()"), path)
        }
    }

    func testAppKitCaptureViewsDrawNoRing() throws {
        for path in ["Settings/ShortcutCapture.swift", "Settings/ClipboardPage.swift"] {
            XCTAssertTrue(try source(path).contains("override var focusRingType: NSFocusRingType"), path)
        }
    }
}
