import Carbon.HIToolbox
import XCTest
@testable import PromptAnnotator

final class HotkeyChordTests: XCTestCase {
    func testDefaultIsOptionSpace() {
        let chord = HotkeyChord.default
        XCTAssertEqual(chord.keyCode, UInt32(kVK_Space))
        XCTAssertEqual(chord.carbonModifiers, UInt32(optionKey))
        XCTAssertTrue(chord.canRegister)
        XCTAssertFalse(chord.takesOverSystemShortcut)
        XCTAssertEqual(chord.display, "⌥Space")
        XCTAssertEqual(chord.keycaps, ["⌥", "Space"])
        XCTAssertNil(chord.rejection)
    }

    func testLegacyDefaultWasControlOptionSpace() {
        let legacy = HotkeyChord.legacyDefault
        XCTAssertEqual(legacy.keyCode, UInt32(kVK_Space))
        XCTAssertEqual(legacy.carbonModifiers, UInt32(controlKey | optionKey))
        XCTAssertEqual(legacy.display, "⌃⌥Space")
        XCTAssertTrue(legacy.canRegister)
    }

    func testSystemSpaceChordsStayReserved() {
        let option = HotkeyChord(keyCode: UInt32(kVK_Space), carbonModifiers: UInt32(optionKey))
        let command = HotkeyChord(keyCode: UInt32(kVK_Space), carbonModifiers: UInt32(cmdKey))
        let both = HotkeyChord(keyCode: UInt32(kVK_Space), carbonModifiers: UInt32(cmdKey | optionKey))
        // ⌥Space is the default — allowed.
        XCTAssertFalse(option.takesOverSystemShortcut)
        XCTAssertTrue(option.canRegister)
        // Spotlight / Finder search stay reserved.
        XCTAssertTrue(command.takesOverSystemShortcut)
        XCTAssertTrue(both.takesOverSystemShortcut)
        XCTAssertFalse(command.canRegister)
        XCTAssertFalse(both.canRegister)
        XCTAssertEqual(
            command.rejection,
            "Command-Space and Option-Command-Space stay with the system."
        )
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

    func testFunctionKeyMayOmitModifiers() {
        let bare = HotkeyChord(keyCode: UInt32(kVK_F8), carbonModifiers: 0)
        XCTAssertTrue(bare.isFunctionKey)
        XCTAssertTrue(bare.canRegister)
        XCTAssertNil(bare.rejection)
        XCTAssertEqual(bare.keycaps, ["F8"])

        let letter = HotkeyChord(keyCode: UInt32(kVK_ANSI_K), carbonModifiers: 0)
        XCTAssertFalse(letter.isFunctionKey)
        XCTAssertFalse(letter.canRegister)
        XCTAssertEqual(letter.rejection, "Add at least one modifier, or use a function key.")
    }

    @MainActor
    func testLegacyDefaultMigratesOnceToOptionSpace() {
        let suiteName = "test.hotkey.migrate.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        defaults.set(Int(kVK_Space), forKey: "hotkey.keyCode")
        defaults.set(Int(controlKey | optionKey), forKey: "hotkey.modifiers")

        let settings = AppSettings(defaults: defaults)
        XCTAssertEqual(settings.chord, .default)
        XCTAssertEqual(settings.chord.display, "⌥Space")
        XCTAssertEqual(defaults.integer(forKey: "hotkey.keyCode"), Int(kVK_Space))
        XCTAssertEqual(defaults.integer(forKey: "hotkey.modifiers"), Int(optionKey))
        XCTAssertTrue(defaults.bool(forKey: "hotkey.migratedToOptionSpace"))

        // After migration, an explicit ⌃⌥Space choice is kept.
        defaults.set(Int(controlKey | optionKey), forKey: "hotkey.modifiers")
        let again = AppSettings(defaults: defaults)
        XCTAssertEqual(again.chord, .legacyDefault)
    }

    @MainActor
    func testCustomChordIsNotMigrated() {
        let suiteName = "test.hotkey.custom.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let custom = HotkeyChord(
            keyCode: UInt32(kVK_ANSI_K),
            carbonModifiers: UInt32(controlKey | optionKey)
        )
        defaults.set(Int(custom.keyCode), forKey: "hotkey.keyCode")
        defaults.set(Int(custom.carbonModifiers), forKey: "hotkey.modifiers")

        let settings = AppSettings(defaults: defaults)
        XCTAssertEqual(settings.chord, custom)
        XCTAssertTrue(defaults.bool(forKey: "hotkey.migratedToOptionSpace"))
    }
}
