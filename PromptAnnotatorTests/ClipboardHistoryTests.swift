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
        XCTAssertEqual(chord.display, "⌘⇧C")
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
    }
}
