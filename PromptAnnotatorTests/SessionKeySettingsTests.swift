import Carbon.HIToolbox
import XCTest
@testable import PromptAnnotator

/// The Screenshot key and Annotate key pickers, and the move from Shift-to-draw.
@MainActor
final class SessionKeySettingsTests: XCTestCase {
    private var suiteName = ""
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "test.sessionkeys.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        super.tearDown()
    }

    private func storeChord(_ chord: HotkeyChord) {
        defaults.set(Int(chord.keyCode), forKey: "hotkey.keyCode")
        defaults.set(Int(chord.carbonModifiers), forKey: "hotkey.modifiers")
        defaults.set(true, forKey: "hotkey.migratedToOptionSpace")
    }

    private func storeCancel(_ chord: HotkeyChord) {
        defaults.set(Int(chord.keyCode), forKey: "hotkey.cancel.keyCode")
        defaults.set(Int(chord.carbonModifiers), forKey: "hotkey.cancel.modifiers")
    }

    func testFreshInstallUsesShiftAndControl() {
        let settings = AppSettings(defaults: defaults)
        XCTAssertEqual(settings.sessionKeys, .standard)
        XCTAssertEqual(defaults.string(forKey: "session.screenshotKey"), "shift")
        XCTAssertEqual(defaults.string(forKey: "session.annotateKey"), "control")
    }

    func testLegacyDefaultUserMovesToOptionSpaceAndControl() {
        defaults.set(Int(kVK_Space), forKey: "hotkey.keyCode")
        defaults.set(Int(controlKey | optionKey), forKey: "hotkey.modifiers")
        let settings = AppSettings(defaults: defaults)
        XCTAssertEqual(settings.chord, .default)
        XCTAssertEqual(settings.screenshotKey, .shift)
        XCTAssertEqual(settings.annotateKey, .control)
    }

    func testChordWithControlMigratesDrawingToOption() {
        let chord = HotkeyChord(keyCode: UInt32(kVK_F5), carbonModifiers: UInt32(controlKey))
        storeChord(chord)
        let settings = AppSettings(defaults: defaults)
        XCTAssertEqual(settings.chord, chord, "the user's shortcut is kept")
        XCTAssertEqual(settings.annotateKey, .option)
    }

    func testChordAndCancelUsingBothLeaveDrawingOff() {
        let chord = HotkeyChord(keyCode: UInt32(kVK_ANSI_K), carbonModifiers: UInt32(controlKey | optionKey))
        storeChord(chord)
        storeCancel(HotkeyChord(keyCode: UInt32(kVK_ANSI_J), carbonModifiers: UInt32(cmdKey | optionKey)))
        let settings = AppSettings(defaults: defaults)
        XCTAssertEqual(settings.chord, chord)
        XCTAssertNil(settings.annotateKey)
        XCTAssertEqual(defaults.string(forKey: "session.annotateKey"), "off")
        XCTAssertNotNil(settings.cancelChord, "a cancel chord without session keys survives")
    }

    func testCancelChordWithControlLeavesDrawingOff() {
        storeCancel(HotkeyChord(keyCode: UInt32(kVK_ANSI_X), carbonModifiers: UInt32(controlKey | cmdKey)))
        let settings = AppSettings(defaults: defaults)
        XCTAssertEqual(settings.chord, .default)
        XCTAssertNil(settings.annotateKey, "⌥Space and ⌃⌘X use both")
    }

    func testStoredChoicesReload() {
        defaults.set("control", forKey: "session.screenshotKey")
        defaults.set("off", forKey: "session.annotateKey")
        let settings = AppSettings(defaults: defaults)
        XCTAssertEqual(settings.screenshotKey, .control)
        XCTAssertNil(settings.annotateKey)
    }

    func testStoredClashWithTheShortcutIsRepaired() {
        defaults.set("option", forKey: "session.screenshotKey")
        defaults.set("control", forKey: "session.annotateKey")
        let settings = AppSettings(defaults: defaults)
        XCTAssertEqual(settings.chord, .default, "⌥Space stays")
        XCTAssertEqual(settings.sessionKeys, .standard)
    }

    func testGarbageIsIgnored() {
        defaults.set("hyper", forKey: "session.screenshotKey")
        defaults.set("shift", forKey: "session.annotateKey")
        let settings = AppSettings(defaults: defaults)
        XCTAssertEqual(settings.sessionKeys, .standard)
    }

    func testPickersRejectDuplicates() {
        let settings = AppSettings(defaults: defaults)
        XCTAssertEqual(
            settings.setScreenshotKey(.control),
            "Control already draws. Change the annotate key first."
        )
        XCTAssertEqual(settings.screenshotKey, .shift)
        XCTAssertNil(settings.setAnnotateKey(nil))
        XCTAssertNil(settings.setScreenshotKey(.control))
        XCTAssertEqual(settings.screenshotKey, .control)
        XCTAssertEqual(
            settings.setAnnotateKey(.control),
            "Control already grabs the screen. Pick another key, or Off."
        )
        XCTAssertNil(settings.annotateKey)
        XCTAssertEqual(defaults.string(forKey: "session.screenshotKey"), "control")
    }

    func testPickersRejectTheShortcutsModifiers() {
        let settings = AppSettings(defaults: defaults)
        XCTAssertEqual(
            settings.setAnnotateKey(.option),
            "Start and stop uses ⌥Space, so Option stays free for it."
        )
        XCTAssertEqual(settings.annotateKey, .control)
        XCTAssertNotNil(settings.setScreenshotKey(.option))
        XCTAssertEqual(settings.screenshotKey, .shift)
    }

    func testRejectionCoversTheCancelChord() {
        let keys = SessionKeys.Bindings(screenshot: .shift, annotate: .control)
        let cancel = HotkeyChord(keyCode: UInt32(kVK_ANSI_X), carbonModifiers: UInt32(controlKey | cmdKey))
        XCTAssertEqual(
            AppSettings.sessionKeyRejection(keys, chord: .default, cancelChord: cancel),
            "Cancel recording uses \(cancel.display), so Control stays free for it."
        )
        XCTAssertNil(AppSettings.sessionKeyRejection(keys, chord: .default, cancelChord: nil))
    }

    func testShortcutsCannotUseTheChosenKeys() {
        let keys = SessionKeys.Bindings.standard
        let control = HotkeyChord(keyCode: UInt32(kVK_ANSI_K), carbonModifiers: UInt32(controlKey | cmdKey))
        XCTAssertEqual(
            control.rejection(reserving: keys),
            "Control is held to draw, so the shortcut cannot include Control."
        )
        XCTAssertNil(control.rejection(reserving: SessionKeys.Bindings(screenshot: .shift, annotate: .option)))
        let shift = HotkeyChord(keyCode: UInt32(kVK_ANSI_K), carbonModifiers: UInt32(shiftKey | cmdKey))
        XCTAssertNil(shift.rejection(reserving: SessionKeys.Bindings(screenshot: .control, annotate: nil)))
        XCTAssertTrue(shift.isRegistrable)
        XCTAssertFalse(HotkeyChord(keyCode: UInt32(kVK_ANSI_K), carbonModifiers: 0).isRegistrable)
    }

    func testSetChordRespectsTheAnnotateKey() {
        let settings = AppSettings(defaults: defaults)
        let control = HotkeyChord(keyCode: UInt32(kVK_ANSI_K), carbonModifiers: UInt32(controlKey | cmdKey))
        XCTAssertFalse(settings.setChord(control))
        XCTAssertFalse(settings.setCancelChord(control))
    }
}
