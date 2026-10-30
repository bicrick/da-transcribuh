import Carbon.HIToolbox
import XCTest
@testable import PromptAnnotator

final class HotkeyChordTests: XCTestCase {
    func testDefaultIsFn() {
        let chord = HotkeyChord.default
        XCTAssertEqual(chord.keyCode, HotkeyChord.fnKeyCode)
        XCTAssertEqual(chord.carbonModifiers, 0)
        XCTAssertTrue(chord.isFnOnly)
        XCTAssertTrue(chord.isSingleKey)
        XCTAssertTrue(chord.isRegistrable)
        XCTAssertFalse(chord.isCarbonRegistrable)
        XCTAssertTrue(chord.canRegister)
        XCTAssertEqual(chord.display, "fn")
        XCTAssertEqual(chord.keycaps, ["fn"])
        XCTAssertNil(chord.rejection)
    }

    func testOptionSpaceFallback() {
        let chord = HotkeyChord.optionSpaceDefault
        XCTAssertEqual(chord.keyCode, UInt32(kVK_Space))
        XCTAssertEqual(chord.carbonModifiers, UInt32(optionKey))
        XCTAssertTrue(chord.isCarbonRegistrable)
        XCTAssertEqual(chord.display, "⌥Space")
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
        XCTAssertFalse(option.takesOverSystemShortcut)
        XCTAssertTrue(option.canRegister)
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
            "Shift is held to grab the screen, so the shortcut cannot include Shift."
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
        XCTAssertEqual(letter.rejection, "Add at least one modifier, use a function key, or pick fn.")
    }

    @MainActor
    func testLegacyDefaultMigratesOnceToFn() {
        let suiteName = "test.hotkey.migrate.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        defaults.set(Int(kVK_Space), forKey: "hotkey.keyCode")
        defaults.set(Int(controlKey | optionKey), forKey: "hotkey.modifiers")

        let settings = AppSettings(defaults: defaults)
        XCTAssertEqual(settings.chord, .default)
        XCTAssertEqual(settings.chord.display, "fn")
        XCTAssertEqual(defaults.integer(forKey: "hotkey.keyCode"), Int(HotkeyChord.fnKeyCode))
        XCTAssertEqual(defaults.integer(forKey: "hotkey.modifiers"), 0)
        XCTAssertTrue(defaults.bool(forKey: "hotkey.migratedToOptionSpace"))

        // After migration, an explicit ⌃⌥Space choice is kept.
        defaults.set(Int(kVK_Space), forKey: "hotkey.keyCode")
        defaults.set(Int(controlKey | optionKey), forKey: "hotkey.modifiers")
        let again = AppSettings(defaults: defaults)
        XCTAssertEqual(again.chord, .legacyDefault)
    }

    @MainActor
    func testStoredOptionSpaceIsKept() {
        let suiteName = "test.hotkey.optionSpace.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        defaults.set(Int(kVK_Space), forKey: "hotkey.keyCode")
        defaults.set(Int(optionKey), forKey: "hotkey.modifiers")
        defaults.set(true, forKey: "hotkey.migratedToOptionSpace")

        let settings = AppSettings(defaults: defaults)
        XCTAssertEqual(settings.chord, .optionSpaceDefault)
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

    @MainActor
    func testFreshInstallDefaultsToHoldAndDoubleTap() {
        let suiteName = "test.hotkey.behavior.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let settings = AppSettings(defaults: defaults)
        XCTAssertEqual(settings.hotkeyBehavior, .holdAndDoubleTap)
        XCTAssertTrue(settings.pushToTalk)
    }

    @MainActor
    func testLegacyPushToTalkBoolMigrates() {
        let suiteName = "test.hotkey.pttMigrate.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        defaults.set(true, forKey: "hotkey.pushToTalk")
        let settings = AppSettings(defaults: defaults)
        XCTAssertEqual(settings.hotkeyBehavior, .holdOnly)

        let suite2 = "test.hotkey.pttMigrate2.\(UUID().uuidString)"
        let defaults2 = UserDefaults(suiteName: suite2)!
        defer { defaults2.removePersistentDomain(forName: suite2) }
        defaults2.set(false, forKey: "hotkey.pushToTalk")
        let settings2 = AppSettings(defaults: defaults2)
        XCTAssertEqual(settings2.hotkeyBehavior, .toggleOnly)
    }
}
