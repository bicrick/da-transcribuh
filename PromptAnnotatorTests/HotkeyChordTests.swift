import Carbon.HIToolbox
import XCTest
@testable import PromptAnnotator

final class HotkeyChordTests: XCTestCase {
    func testDefaultIsControlOptionSpace() {
        let chord = HotkeyChord.default
        XCTAssertEqual(chord.keyCode, UInt32(kVK_Space))
        XCTAssertTrue(chord.canRegister)
        XCTAssertFalse(chord.takesOverSystemShortcut)
        XCTAssertEqual(chord.display, "⌃⌥Space")
    }

    func testSystemSpaceChordsStayReserved() {
        let option = HotkeyChord(keyCode: UInt32(kVK_Space), carbonModifiers: UInt32(optionKey))
        let command = HotkeyChord(keyCode: UInt32(kVK_Space), carbonModifiers: UInt32(cmdKey))
        let both = HotkeyChord(keyCode: UInt32(kVK_Space), carbonModifiers: UInt32(cmdKey | optionKey))
        XCTAssertTrue(option.takesOverSystemShortcut)
        XCTAssertTrue(command.takesOverSystemShortcut)
        XCTAssertTrue(both.takesOverSystemShortcut)
        XCTAssertFalse(option.canRegister)
        XCTAssertFalse(command.canRegister)
        XCTAssertFalse(both.canRegister)
    }

    func testShiftCannotBePartOfTheShortcut() {
        let chord = HotkeyChord(
            keyCode: UInt32(kVK_ANSI_K),
            carbonModifiers: UInt32(controlKey | shiftKey)
        )
        XCTAssertTrue(chord.includesShift)
        XCTAssertFalse(chord.canRegister)
        XCTAssertEqual(
            chord.rejection,
            "Shift is held to draw, so the shortcut cannot include Shift."
        )
    }

    func testControlOptionKIsAllowed() {
        let chord = HotkeyChord(
            keyCode: UInt32(kVK_ANSI_K),
            carbonModifiers: UInt32(controlKey | optionKey)
        )
        XCTAssertTrue(chord.canRegister)
        XCTAssertEqual(chord.display, "⌃⌥K")
        XCTAssertNil(chord.rejection)
    }
}
