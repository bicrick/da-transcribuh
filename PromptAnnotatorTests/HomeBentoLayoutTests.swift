import AppKit
import XCTest
@testable import PromptAnnotator

final class HomeBentoLayoutTests: XCTestCase {
    func testStackBreakpointIs720() {
        XCTAssertEqual(HomeBentoLayout.stackBreakpoint, 720)
        XCTAssertFalse(HomeBentoLayout.isNarrow(contentWidth: 720))
        XCTAssertFalse(HomeBentoLayout.isNarrow(contentWidth: 1000))
        XCTAssertTrue(HomeBentoLayout.isNarrow(contentWidth: 719))
        XCTAssertTrue(HomeBentoLayout.isNarrow(contentWidth: 630))
    }

    func testRecordingChordCaptureMessages() {
        XCTAssertNil(RecordingChordCapture.message(for: .cancelled))
        XCTAssertNil(RecordingChordCapture.message(for: .saved(success: true)))
        XCTAssertNil(RecordingChordCapture.message(for: .restoredDefault(success: true)))
        XCTAssertEqual(
            RecordingChordCapture.message(for: .rejected("Add at least one modifier, or use a function key.")),
            "Add at least one modifier, or use a function key."
        )
        XCTAssertEqual(
            RecordingChordCapture.message(for: .saved(success: false)),
            "That shortcut is already used, or macOS would not register it."
        )
        XCTAssertEqual(
            RecordingChordCapture.message(for: .restoredDefault(success: false)),
            "macOS would not register the default shortcut."
        )
    }

    @MainActor
    func testRecordingChordCaptureEscCancelsWithoutChangingChord() {
        let name = "PromptAnnotatorTests.homeChordEsc"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        let settings = AppSettings(defaults: defaults)
        let before = settings.chord
        // Install a stub-friendly chord path: setChord may fail to register in CI without
        // a real HotkeyCenter session — Esc must still report cancelled and leave storage alone.
        let esc = NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: "\u{1b}",
            charactersIgnoringModifiers: "\u{1b}",
            isARepeat: false,
            keyCode: 53
        )!
        let outcome = RecordingChordCapture.applyToggleEvent(esc, settings: settings)
        XCTAssertEqual(outcome, .cancelled)
        XCTAssertEqual(settings.chord, before)
        defaults.removePersistentDomain(forName: name)
    }

    @MainActor
    func testRecordingChordCaptureRejectsBareLetter() {
        let name = "PromptAnnotatorTests.homeChordReject"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        let settings = AppSettings(defaults: defaults)
        let event = NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: "a",
            charactersIgnoringModifiers: "a",
            isARepeat: false,
            keyCode: 0
        )!
        let outcome = RecordingChordCapture.applyToggleEvent(event, settings: settings)
        if case .rejected(let reason) = outcome {
            XCTAssertTrue(reason.contains("modifier") || reason.contains("function"))
        } else {
            XCTFail("expected rejected, got \(outcome)")
        }
        defaults.removePersistentDomain(forName: name)
    }
}
