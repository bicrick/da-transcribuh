import Carbon.HIToolbox
import XCTest
@testable import PromptAnnotator

@MainActor
final class ClipboardHistoryTests: XCTestCase {
    private var folder: URL!
    private var store: ClipboardHistoryStore!

    override func setUp() async throws {
        folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("clipboard-test-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        store = ClipboardHistoryStore(folder: folder)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: folder)
    }

    func testDedupeMovesExistingToTopAndBumpsCopyCount() {
        _ = store.ingest(
            kind: .text, source: .pasteboard, text: "hello",
            imagePNG: nil, filePaths: nil, fingerprint: ClipboardFingerprint.text("hello")
        )
        _ = store.ingest(
            kind: .text, source: .pasteboard, text: "world",
            imagePNG: nil, filePaths: nil, fingerprint: ClipboardFingerprint.text("world")
        )
        XCTAssertEqual(store.items.map(\.text), ["world", "hello"])
        _ = store.ingest(
            kind: .text, source: .pasteboard, text: "hello",
            imagePNG: nil, filePaths: nil, fingerprint: ClipboardFingerprint.text("hello")
        )
        XCTAssertEqual(store.items.count, 2)
        XCTAssertEqual(store.items.first?.text, "hello")
        XCTAssertEqual(store.items.first?.copyCount, 2)
    }

    func testSensitiveTypesAreDetected() {
        let board = NSPasteboard(name: .init("test.clip.\(UUID().uuidString)"))
        board.clearContents()
        board.setString("secret", forType: .string)
        board.setString("1", forType: ClipboardPasteboardTypes.concealed)
        XCTAssertTrue(ClipboardPasteboardTypes.isSensitive(board))
        board.clearContents()
        board.setString("ok", forType: .string)
        XCTAssertFalse(ClipboardPasteboardTypes.isSensitive(board))
    }

    func testPinOrdering() {
        _ = store.ingest(
            kind: .text, source: .pasteboard, text: "a",
            imagePNG: nil, filePaths: nil, fingerprint: "a"
        )
        _ = store.ingest(
            kind: .text, source: .pasteboard, text: "b",
            imagePNG: nil, filePaths: nil, fingerprint: "b"
        )
        let idA = store.items.first(where: { $0.text == "a" })!.id
        store.togglePin(idA)
        let ordered = store.orderedForDisplay(filter: "")
        XCTAssertEqual(ordered.first?.text, "a")
        XCTAssertTrue(ordered.first?.pinned == true)
    }

    func testHistoryLimitDropsOldestUnpinned() {
        store.historyLimitOverride = 5
        for i in 0..<8 {
            _ = store.ingest(
                kind: .text, source: .pasteboard, text: "item-\(i)",
                imagePNG: nil, filePaths: nil, fingerprint: "f-\(i)"
            )
        }
        XCTAssertEqual(store.items.count, 5)
        let pinID = store.items[0].id
        store.togglePin(pinID)
        for i in 8..<12 {
            _ = store.ingest(
                kind: .text, source: .pasteboard, text: "item-\(i)",
                imagePNG: nil, filePaths: nil, fingerprint: "f-\(i)"
            )
        }
        XCTAssertTrue(store.items.contains(where: { $0.id == pinID && $0.pinned }))
        XCTAssertEqual(store.items.count, 5)
        store.clearHistory(keepingPinned: true)
        XCTAssertEqual(store.items.count, 1)
        XCTAssertTrue(store.items[0].pinned)
    }

    func testEmptySessionExclusion() {
        XCTAssertTrue(ClipboardEmptySession.shouldSkip(transcript: nil, imagePNG: nil))
        XCTAssertTrue(ClipboardEmptySession.shouldSkip(transcript: "   ", imagePNG: nil))
        XCTAssertTrue(ClipboardEmptySession.shouldSkip(transcript: "[BLANK_AUDIO]", imagePNG: nil))
        XCTAssertTrue(ClipboardEmptySession.shouldSkip(transcript: "(silence)", imagePNG: nil))
        XCTAssertFalse(ClipboardEmptySession.shouldSkip(transcript: "hello", imagePNG: nil))
        XCTAssertFalse(ClipboardEmptySession.shouldSkip(transcript: nil, imagePNG: Data([1, 2, 3])))
        XCTAssertFalse(ClipboardEmptySession.shouldSkip(transcript: "   ", imagePNG: Data([1])))

        ClipboardHistoryController.shared.store.historyLimitOverride = 50
        // Use isolated store via controller path — exercise controller against shared store carefully.
        let before = ClipboardHistoryStore.shared.items.count
        ClipboardHistoryController.shared.ingestSession(transcript: "", imagePNG: nil)
        ClipboardHistoryController.shared.ingestSession(transcript: "[BLANK_AUDIO]", imagePNG: nil)
        XCTAssertEqual(ClipboardHistoryStore.shared.items.count, before)

        // Local store path: empty skip is pure; ingest on local store still works for speech.
        let countBefore = store.items.count
        _ = store.ingest(
            kind: .text, source: .transcript, text: "kept",
            imagePNG: nil, filePaths: nil, fingerprint: "kept"
        )
        XCTAssertEqual(store.items.count, countBefore + 1)
    }

    func testClipboardDefaultChordAllowsShift() {
        let chord = HotkeyChord.clipboardDefault
        // Apple menu order is ⌃⌥⇧⌘, so ⌘⇧C renders as "⇧⌘C" (same as every other chord).
        XCTAssertEqual(chord.display, "⇧⌘C")
        XCTAssertTrue(chord.canRegister(allowingShift: true))
        XCTAssertFalse(chord.canRegister(allowingShift: false))
        XCTAssertNil(chord.rejection(allowingShift: true))
    }

    func testOnboardingStepsIncludeClipboardAndAppearance() {
        let labels = OnboardingStep.allCases.map(\.title)
        XCTAssertTrue(labels.contains("Clipboard history"))
        XCTAssertTrue(labels.contains("Appearance"))
        XCTAssertTrue(labels.contains("Keybinds"))
        XCTAssertEqual(OnboardingStep.railLabels.count, OnboardingStep.allCases.count)
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

    func testOwnWriteSuppressNestsAndClears() {
        let store = ClipboardHistoryStore.shared
        let before = store.suppressWatcher
        var ended = 0
        let previous = store.onOwnWriteEnded
        store.onOwnWriteEnded = { ended += 1 }
        defer { store.onOwnWriteEnded = previous }

        store.beginOwnWrite()
        store.beginOwnWrite()
        XCTAssertEqual(store.suppressWatcher, before + 2)
        store.endOwnWrite()
        XCTAssertEqual(store.suppressWatcher, before + 1)
        XCTAssertEqual(ended, 0, "nested end must not fire until fully clear")
        store.endOwnWrite()
        XCTAssertEqual(store.suppressWatcher, before)
        XCTAssertEqual(ended, 1, "watcher must sync changeCount when suppress hits 0")
    }

    @MainActor
    func testRecordingChordRejectsClipboardChord() {
        let name = "clipboard-chord-collision-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        let settings = AppSettings(defaults: defaults)
        let clip = HotkeyChord.clipboardDefault
        XCTAssertTrue(settings.setClipboardChord(clip))
        // Recording chords forbid Shift; use a no-Shift clipboard-shaped chord.
        let clash = HotkeyChord(keyCode: clip.keyCode, carbonModifiers: UInt32(cmdKey | optionKey))
        if clash.canRegister {
            _ = settings.setClipboardChord(clash)
            XCTAssertFalse(settings.setChord(clash))
            XCTAssertFalse(settings.setCancelChord(clash))
        }
        defaults.removePersistentDomain(forName: name)
    }

    func testCarbonHotKeyIdsDoNotCollide() {
        // record=1 (HotkeyCenter), paste=2 (PasteFollowUp), cancel=3, clipboard=4.
        XCTAssertEqual(ClipboardHistoryController.carbonHotKeyID, 4)
        XCTAssertNotEqual(ClipboardHistoryController.carbonHotKeyID, 1)
        XCTAssertNotEqual(ClipboardHistoryController.carbonHotKeyID, 2)
        XCTAssertNotEqual(ClipboardHistoryController.carbonHotKeyID, 3)
    }
}

/// "At cursor" placement math. The pointer must stay outside the panel, so the hotkey's
/// follow-up click or hover can't land on a row.
final class ClipboardCursorPlacementTests: XCTestCase {
    private let size = CGSize(width: 458, height: 488)
    private let laptop = CGRect(x: 0, y: 0, width: 1512, height: 944)

    private func place(_ mouse: CGPoint, in visible: CGRect) -> CGRect {
        ClipboardCursorPlacement.frame(mouse: mouse, size: size, visible: visible)
    }

    private func assertFits(_ frame: CGRect, in visible: CGRect, file: StaticString = #filePath, line: UInt = #line) {
        let inset = visible.insetBy(dx: ClipboardCursorPlacement.margin, dy: ClipboardCursorPlacement.margin)
        XCTAssertTrue(inset.contains(frame), "\(frame) not inside \(inset)", file: file, line: line)
    }

    /// The pointer is outside, not on the edge either (hover tracking counts the edge).
    private func assertPointerOutside(_ frame: CGRect, _ mouse: CGPoint, file: StaticString = #filePath, line: UInt = #line) {
        let grown = frame.insetBy(dx: -1, dy: -1)
        XCTAssertFalse(grown.contains(mouse), "pointer \(mouse) touches \(frame)", file: file, line: line)
    }

    func testOpensRightOfAndBelowThePointer() {
        let mouse = CGPoint(x: 400, y: 700)
        let frame = place(mouse, in: laptop)
        let gap = ClipboardCursorPlacement.gap
        XCTAssertEqual(frame.minX, mouse.x + gap)
        XCTAssertEqual(frame.maxY, mouse.y - gap)
        XCTAssertEqual(frame.size, size)
        assertPointerOutside(frame, mouse)
        assertFits(frame, in: laptop)
    }

    func testFlipsLeftAtTheRightEdge() {
        let mouse = CGPoint(x: 1400, y: 700)
        let frame = place(mouse, in: laptop)
        XCTAssertEqual(frame.maxX, mouse.x - ClipboardCursorPlacement.gap)
        XCTAssertEqual(frame.maxY, mouse.y - ClipboardCursorPlacement.gap)
        assertPointerOutside(frame, mouse)
        assertFits(frame, in: laptop)
    }

    func testFlipsUpAtTheBottomEdge() {
        let mouse = CGPoint(x: 400, y: 120)
        let frame = place(mouse, in: laptop)
        XCTAssertEqual(frame.minX, mouse.x + ClipboardCursorPlacement.gap)
        XCTAssertEqual(frame.minY, mouse.y + ClipboardCursorPlacement.gap)
        assertPointerOutside(frame, mouse)
        assertFits(frame, in: laptop)
    }

    func testFlipsBothWaysInTheBottomRightCorner() {
        let mouse = CGPoint(x: 1500, y: 10)
        let frame = place(mouse, in: laptop)
        XCTAssertEqual(frame.maxX, mouse.x - ClipboardCursorPlacement.gap)
        XCTAssertEqual(frame.minY, mouse.y + ClipboardCursorPlacement.gap)
        assertPointerOutside(frame, mouse)
        assertFits(frame, in: laptop)
    }

    func testTopLeftCornerStaysBesideThePointer() {
        let mouse = CGPoint(x: 2, y: 940)
        let frame = place(mouse, in: laptop)
        assertPointerOutside(frame, mouse)
        assertFits(frame, in: laptop)
    }

    func testShortScreenClampsVerticallyButKeepsThePointerOutside() {
        // Neither above nor below fits, so y clamps. The side offset still keeps the pointer out.
        let short = CGRect(x: 0, y: 0, width: 1512, height: 600)
        let mouse = CGPoint(x: 300, y: 300)
        let frame = place(mouse, in: short)
        assertFits(frame, in: short)
        assertPointerOutside(frame, mouse)
        XCTAssertEqual(frame.minX, mouse.x + ClipboardCursorPlacement.gap)
    }

    func testSecondaryScreenLeftOfThePrimary() {
        // External display to the left: negative x, taller, menu bar inset at the top.
        let external = CGRect(x: -1920, y: -136, width: 1920, height: 1055)
        for mouse in [CGPoint(x: -1900, y: 900), CGPoint(x: -5, y: 900), CGPoint(x: -5, y: -130), CGPoint(x: -960, y: 400)] {
            let frame = place(mouse, in: external)
            assertPointerOutside(frame, mouse)
            assertFits(frame, in: external)
        }
    }

    func testPointerNeverInsideAcrossTheWholeScreen() {
        for x in stride(from: laptop.minX, through: laptop.maxX - 1, by: 37) {
            for y in stride(from: laptop.minY, through: laptop.maxY - 1, by: 29) {
                let mouse = CGPoint(x: x, y: y)
                let frame = place(mouse, in: laptop)
                assertPointerOutside(frame, mouse)
                assertFits(frame, in: laptop)
            }
        }
    }
}
