import XCTest
@testable import PromptAnnotator

@MainActor
final class ClipboardSettingsTests: XCTestCase {
    func testClipboardPreferencesRoundTrip() {
        let name = "clipboard-prefs-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        let settings = AppSettings(defaults: defaults)

        settings.setClipboardPasteAutomatically(false)
        settings.setClipboardSaveImages(false)
        settings.setClipboardSortMode(.copyCount)
        settings.setClipboardPopupPosition(.screenCenter)
        settings.setClipboardPinEdge(.bottom)
        settings.setClipboardImageHeight(48)
        settings.setClipboardPreviewDelayMs(250)
        settings.setClipboardShowFooter(false)
        settings.setClipboardIgnoreConcealed(false)
        settings.setClipboardCapturePaused(true)
        settings.addClipboardIgnoredApp("com.example.vault")

        let again = AppSettings(defaults: defaults)
        XCTAssertFalse(again.clipboardPasteAutomatically)
        XCTAssertFalse(again.clipboardSaveImages)
        XCTAssertEqual(again.clipboardSortMode, .copyCount)
        XCTAssertEqual(again.clipboardPopupPosition, .screenCenter)
        XCTAssertEqual(again.clipboardPinEdge, .bottom)
        XCTAssertEqual(again.clipboardImageHeight, 48, accuracy: 0.1)
        XCTAssertEqual(again.clipboardPreviewDelayMs, 250)
        XCTAssertFalse(again.clipboardShowFooter)
        XCTAssertFalse(again.clipboardIgnoreConcealed)
        XCTAssertTrue(again.clipboardCapturePaused)
        XCTAssertEqual(again.clipboardIgnoredApps, ["com.example.vault"])

        defaults.removePersistentDomain(forName: name)
    }

    func testSortModesAndPinEdgeAffectOrdering() throws {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("clip-sort-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let store = ClipboardHistoryStore(folder: folder)
        let settings = AppSettings.shared
        let previousSort = settings.clipboardSortMode
        let previousEdge = settings.clipboardPinEdge
        defer {
            settings.setClipboardSortMode(previousSort)
            settings.setClipboardPinEdge(previousEdge)
        }

        _ = store.ingest(
            kind: .text, source: .pasteboard, text: "alpha",
            imagePNG: nil, filePaths: nil, fingerprint: "a"
        )
        _ = store.ingest(
            kind: .text, source: .pasteboard, text: "beta",
            imagePNG: nil, filePaths: nil, fingerprint: "b"
        )
        guard let second = store.items.first(where: { $0.fingerprint == "b" }) else {
            return XCTFail("missing item")
        }
        store.togglePin(second.id)
        store.updatePinMetadata(id: second.id, title: "Pinned Beta", key: "B")

        settings.setClipboardSortMode(.copyCount)
        settings.setClipboardPinEdge(.top)
        let top = store.orderedForDisplay(filter: "")
        XCTAssertEqual(top.first?.pinTitle, "Pinned Beta")
        XCTAssertEqual(top.first?.pinKey, "B")

        settings.setClipboardPinEdge(.bottom)
        let bottom = store.orderedForDisplay(filter: "")
        XCTAssertEqual(bottom.last?.pinTitle, "Pinned Beta")
    }

    func testSoftSelectionColorsAreNotHardInvert() {
        // Smoke: tokens exist and differ from hard label/window invert.
        XCTAssertNotEqual(Ink.rowSelect, Ink.label)
        XCTAssertNotEqual(Ink.rowHover, Ink.window)
    }

    func testSettingsPageIncludesClipboardTab() {
        XCTAssertTrue(SettingsPage.tabOrder.contains(.clipboard))
        XCTAssertEqual(SettingsPage.clipboard.title, "Clipboard")
    }
}
