import AppKit
import XCTest
@testable import PromptAnnotator

/// A take's collage and transcript as one linked history entry: ingest,
/// migration of legacy pairs, the two-item pasteboard, and the sequential paste.
/// Isolated store folders and named pasteboards only (never `.general`).
@MainActor
final class LinkedSessionEntryTests: XCTestCase {
    private var folder: URL!
    private var store: ClipboardHistoryStore!
    private var boards: [NSPasteboard] = []

    override func setUp() async throws {
        folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("clipboard-linked-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        store = ClipboardHistoryStore(folder: folder)
        store.historyLimitOverride = 50
    }

    override func tearDown() async throws {
        boards.forEach { $0.releaseGlobally() }
        boards = []
        ClipboardHistoryStore.flushPendingWrites()
        try? FileManager.default.removeItem(at: folder)
    }

    private func board() -> NSPasteboard {
        let pb = NSPasteboard(name: .init("test.clip.linked.\(UUID().uuidString)"))
        pb.clearContents()
        boards.append(pb)
        return pb
    }

    private func png(_ w: Int = 24, _ h: Int = 16, red: CGFloat = 0.8) -> Data {
        let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: w, pixelsHigh: h, bitsPerSample: 8,
            samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
            bytesPerRow: 0, bitsPerPixel: 0
        )!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSColor(red: red, green: 0.2, blue: 0.1, alpha: 1).setFill()
        NSRect(x: 0, y: 0, width: w, height: h).fill()
        NSGraphicsContext.restoreGraphicsState()
        return rep.representation(using: .png, properties: [:])!
    }

    // MARK: Ingest

    func testTakeWithCollageAndWordsIsOneLinkedRow() throws {
        let image = png()
        ClipboardHistoryController.ingestSession(transcript: "  look at this button  ", imagePNG: image, into: store)
        XCTAssertEqual(store.items.count, 1)
        let item = try XCTUnwrap(store.items.first)
        XCTAssertTrue(item.isLinkedSession)
        XCTAssertTrue(item.isMixed)
        XCTAssertEqual(item.kind, .text)
        XCTAssertEqual(item.source, .transcript)
        XCTAssertEqual(item.text, "look at this button")
        XCTAssertEqual(store.imagePNGData(for: item), image)
        XCTAssertEqual(item.fingerprint, ClipboardFingerprint.linked(text: "look at this button", png: image))
        XCTAssertEqual(item.displayApplication, "da transcribuh")

        // Same take again bumps the one row.
        ClipboardHistoryController.ingestSession(transcript: "look at this button", imagePNG: image, into: store)
        XCTAssertEqual(store.items.count, 1)
        XCTAssertEqual(store.items.first?.copyCount, 2)

        // Survives a reload.
        ClipboardHistoryStore.flushPendingWrites()
        let reloaded = ClipboardHistoryStore(folder: folder)
        XCTAssertEqual(reloaded.items.count, 1)
        XCTAssertTrue(try XCTUnwrap(reloaded.items.first).isLinkedSession)
    }

    func testSinglePartTakesKeepTheirOwnRows() {
        ClipboardHistoryController.ingestSession(transcript: "", imagePNG: png(), into: store)
        XCTAssertEqual(store.items.first?.kind, .image)
        XCTAssertEqual(store.items.first?.source, .screenshot)
        ClipboardHistoryController.ingestSession(transcript: "just words", imagePNG: nil, into: store)
        XCTAssertEqual(store.items.count, 2)
        XCTAssertEqual(store.items.first?.kind, .text)
        XCTAssertFalse(store.items[0].isLinkedSession)
        XCTAssertFalse(store.items[1].isLinkedSession)
        // Non-speech only counts as no words: the collage stays an image row.
        ClipboardHistoryController.ingestSession(transcript: "[BLANK_AUDIO]", imagePNG: png(30, 20), into: store)
        XCTAssertEqual(store.items.first?.kind, .image)
    }

    func testWebMixedCopyIsNotALinkedTake() throws {
        let item = try XCTUnwrap(store.ingest(
            payload: .mixed(text: "from safari", png: png()), source: .pasteboard, applicationName: "Safari"
        ))
        XCTAssertTrue(item.isMixed)
        XCTAssertFalse(item.isLinkedSession)
    }

    func testPinAndDeleteActOnBothParts() throws {
        ClipboardHistoryController.ingestSession(transcript: "pin me", imagePNG: png(), into: store)
        let item = try XCTUnwrap(store.items.first)
        let file = folder.appendingPathComponent("images").appendingPathComponent(try XCTUnwrap(item.imageFileName))
        store.togglePin(item.id)
        XCTAssertEqual(store.items.filter(\.pinned).count, 1)
        XCTAssertTrue(store.items[0].hasImage)
        store.delete(item.id)
        XCTAssertTrue(store.items.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
    }

    func testLinkedRowUsesOnlyLegacyKeys() throws {
        // Older builds decode it as a mixed copy: no new keys, no new enum values.
        ClipboardHistoryController.ingestSession(transcript: "old builds", imagePNG: png(), into: store)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(try XCTUnwrap(store.items.first))
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let legacy: Set<String> = [
            "id", "createdAt", "kind", "source", "text", "imageFileName", "filePaths", "pinned", "fingerprint",
            "applicationName", "firstCopiedAt", "lastCopiedAt", "copyCount", "imageWidth", "imageHeight",
            "pinTitle", "pinKey",
        ]
        XCTAssertTrue(Set(object.keys).isSubset(of: legacy))
        XCTAssertEqual(object["kind"] as? String, "text")
        XCTAssertEqual(object["source"] as? String, "transcript")
    }

    // MARK: Migration

    private func writeIndex(_ json: String, images: [String], to dir: URL) throws {
        try FileManager.default.createDirectory(
            at: dir.appendingPathComponent("images"), withIntermediateDirectories: true
        )
        try Data(json.utf8).write(to: dir.appendingPathComponent("index.json"))
        for name in images {
            try png().write(to: dir.appendingPathComponent("images/\(name)"))
        }
    }

    func testLegacyScreenshotTranscriptPairMergesIntoOneRow() throws {
        let legacy = """
        [
          {"id":"11111111-0000-0000-0000-000000000001","createdAt":"2026-10-20T12:00:00Z",
           "firstCopiedAt":"2026-10-20T12:00:00Z","lastCopiedAt":"2026-10-20T12:00:00Z",
           "kind":"text","source":"transcript","text":"the words","pinned":false,
           "fingerprint":"text:aaa","applicationName":"da transcribuh","copyCount":1},
          {"id":"11111111-0000-0000-0000-000000000002","createdAt":"2026-10-20T12:00:00Z",
           "firstCopiedAt":"2026-10-20T12:00:00Z","lastCopiedAt":"2026-10-20T12:00:00Z",
           "kind":"image","source":"screenshot","imageFileName":"pair.png","pinned":true,
           "fingerprint":"image:bbb","applicationName":"da transcribuh","imageWidth":24,"imageHeight":16,
           "copyCount":2},
          {"id":"11111111-0000-0000-0000-000000000003","createdAt":"2026-10-20T11:00:00Z",
           "kind":"text","source":"transcript","text":"older, no picture","pinned":false,
           "fingerprint":"text:ccc"},
          {"id":"11111111-0000-0000-0000-000000000004","createdAt":"2026-10-20T10:00:00Z",
           "kind":"image","source":"screenshot","imageFileName":"lonely.png","pinned":false,
           "fingerprint":"image:ddd"},
          {"id":"11111111-0000-0000-0000-000000000005","createdAt":"2026-10-20T11:00:00Z",
           "kind":"text","source":"pasteboard","text":"copied text","pinned":false,
           "fingerprint":"text:eee"}
        ]
        """
        let dir = folder.appendingPathComponent("legacy", isDirectory: true)
        try writeIndex(legacy, images: ["pair.png", "lonely.png"], to: dir)
        let migrated = ClipboardHistoryStore(folder: dir)
        XCTAssertEqual(migrated.items.count, 4)
        let linked = try XCTUnwrap(migrated.items.first { $0.isLinkedSession })
        XCTAssertEqual(linked.id.uuidString, "11111111-0000-0000-0000-000000000001")
        XCTAssertEqual(linked.text, "the words")
        XCTAssertEqual(linked.imageFileName, "pair.png")
        XCTAssertEqual(linked.fingerprint, "linked:aaa:bbb")
        XCTAssertTrue(linked.pinned)
        XCTAssertEqual(linked.copyCount, 2)
        XCTAssertEqual(linked.imageWidth, 24)
        XCTAssertNotNil(migrated.image(for: linked))
        // Unpaired rows are untouched.
        XCTAssertNotNil(migrated.items.first { $0.text == "older, no picture" && !$0.hasImage })
        XCTAssertNotNil(migrated.items.first { $0.imageFileName == "lonely.png" && $0.kind == .image })
        XCTAssertNotNil(migrated.items.first { $0.text == "copied text" })
        XCTAssertTrue(FileManager.default.fileExists(atPath: dir.appendingPathComponent("images/lonely.png").path))

        // Written back once; a second load is a no-op.
        ClipboardHistoryStore.flushPendingWrites()
        let again = ClipboardHistoryStore(folder: dir)
        XCTAssertEqual(again.items.map(\.id), migrated.items.map(\.id))
        XCTAssertEqual(again.items.filter(\.isLinkedSession).count, 1)
    }

    func testMigrationSkipsFarApartAndConflictingPins() {
        func row(_ n: Int, _ kind: ClipboardPayloadKind, _ source: ClipboardItemSource, at seconds: TimeInterval,
                 pinKey: String? = nil) -> ClipboardItem {
            let date = Date(timeIntervalSince1970: 1_800_000_000 + seconds)
            return ClipboardItem(
                id: UUID(), createdAt: date, kind: kind, source: source,
                text: kind == .text ? "words \(n)" : nil,
                imageFileName: kind == .image ? "\(n).png" : nil, filePaths: nil,
                pinned: pinKey != nil, fingerprint: kind == .text ? "text:\(n)" : "image:\(n)",
                pinKey: pinKey
            )
        }
        let farApart = [row(1, .text, .transcript, at: 0), row(2, .image, .screenshot, at: 5)]
        XCTAssertEqual(ClipboardSessionLinkMigration.merge(farApart).merged, 0)
        let conflicting = [
            row(3, .text, .transcript, at: 0, pinKey: "a"), row(4, .image, .screenshot, at: 0.01, pinKey: "b"),
        ]
        XCTAssertEqual(ClipboardSessionLinkMigration.merge(conflicting).merged, 0)
        // Two takes close together pair one to one, nearest first.
        let two = [
            row(5, .text, .transcript, at: 0), row(6, .image, .screenshot, at: 0.002),
            row(7, .text, .transcript, at: 1.0), row(8, .image, .screenshot, at: 1.003),
        ]
        let merged = ClipboardSessionLinkMigration.merge(two)
        XCTAssertEqual(merged.merged, 2)
        XCTAssertEqual(merged.items.map(\.fingerprint), ["linked:5:6", "linked:7:8"])
    }

    // MARK: Pasteboard

    func testLinkedEntryWritesTwoPasteboardItems() throws {
        let image = png()
        ClipboardHistoryController.ingestSession(transcript: "two items", imagePNG: image, into: store)
        let item = try XCTUnwrap(store.items.first)
        let pb = board()
        XCTAssertTrue(ClipboardHistoryController.write(item, store: store, plainOnly: false, to: pb))
        let items = try XCTUnwrap(pb.pasteboardItems)
        XCTAssertEqual(items.count, 2)
        XCTAssertEqual(items[0].data(forType: .png), image)
        XCTAssertNotNil(items[0].data(forType: .tiff))
        XCTAssertNotNil(items[0].data(forType: .rtfd))
        XCTAssertNil(items[0].string(forType: .string))
        XCTAssertEqual(items[1].string(forType: .string), "two items")
        XCTAssertNil(items[1].data(forType: .png))
        // Legacy single-type readers still find each part.
        XCTAssertEqual(pb.string(forType: .string), "two items")
        XCTAssertEqual(pb.data(forType: .png), image)
    }

    func testRichAndPlainTextViewsReadTheLinkedBoard() throws {
        let pb = board()
        XCTAssertTrue(SessionClipboard.writeLinked(png: png(), tiff: nil, text: "under the picture", to: pb))
        let rich = NSTextView(frame: NSRect(x: 0, y: 0, width: 300, height: 200))
        rich.isRichText = true
        rich.importsGraphics = true
        XCTAssertTrue(rich.readSelection(from: pb))
        XCTAssertTrue(try XCTUnwrap(rich.textStorage).containsAttachments)
        XCTAssertTrue(rich.string.hasSuffix("under the picture"))
        XCTAssertEqual(rich.string.components(separatedBy: "under the picture").count, 2)
        let plain = NSTextView(frame: NSRect(x: 0, y: 0, width: 300, height: 200))
        plain.isRichText = false
        XCTAssertTrue(plain.readSelection(from: pb))
        XCTAssertEqual(plain.string, "under the picture")
    }

    func testImageOnlyRTFDHoldsThePNGBytes() throws {
        let image = png(40, 30)
        let rtfd = try XCTUnwrap(SessionClipboard.rtfdImageOnly(png: image))
        let string = try XCTUnwrap(NSAttributedString(rtfd: rtfd, documentAttributes: nil))
        var attachment: NSTextAttachment?
        string.enumerateAttribute(.attachment, in: NSRange(location: 0, length: string.length)) { value, _, _ in
            attachment = attachment ?? value as? NSTextAttachment
        }
        XCTAssertEqual(attachment?.fileWrapper?.regularFileContents, image)
    }

    // MARK: Sequential paste

    private struct Snapshot: Equatable {
        var items: Int
        var hasPNG: Bool
        var string: String?
    }

    private func snapshot(_ pb: NSPasteboard) -> Snapshot {
        Snapshot(items: pb.pasteboardItems?.count ?? 0, hasPNG: pb.data(forType: .png) != nil,
                 string: pb.string(forType: .string))
    }

    private func spin(_ seconds: TimeInterval) {
        RunLoop.main.run(until: Date().addingTimeInterval(seconds))
    }

    func testSequencePastesPictureThenWordsThenRestoresTheLinkedBoard() {
        let pb = board()
        var posts: [Snapshot] = []
        let paster = PasteFollowUp(board: pb, poster: { posts.append(self.snapshot(pb)) },
                                   delays: (followUp: 0.05, idle: 0.05, restore: 0.1))
        paster.pasteSequence(png: png(), tiff: nil, transcript: "said over it")
        spin(0.3)
        XCTAssertEqual(posts, [
            Snapshot(items: 1, hasPNG: true, string: nil),
            Snapshot(items: 1, hasPNG: false, string: "\nsaid over it"),
        ])
        XCTAssertEqual(snapshot(pb), Snapshot(items: 2, hasPNG: true, string: "said over it"))
    }

    func testRestoreSkipsWhenTheBoardChangedAfterThePaste() {
        let pb = board()
        var posts = 0
        let paster = PasteFollowUp(board: pb, poster: { posts += 1 },
                                   delays: (followUp: 0.03, idle: 0.03, restore: 0.15))
        paster.pasteSequence(png: png(), tiff: nil, transcript: "words")
        spin(0.08)
        XCTAssertEqual(posts, 2)
        pb.clearContents()
        pb.setString("user copied something", forType: .string)
        spin(0.25)
        XCTAssertEqual(pb.string(forType: .string), "user copied something")
        XCTAssertEqual(pb.pasteboardItems?.count, 1)
    }

    func testDefaultDelaysAreTheShippedOnes() {
        XCTAssertEqual(PasteFollowUp.followUpDelay, 0.35)
        XCTAssertGreaterThanOrEqual(PasteFollowUp.restoreDelay, 0.5)
    }

    func testHeldPasteReusesTheStagedBoardOnlyWhenUnchanged() {
        let pb = board()
        let paster = PasteFollowUp(board: pb, poster: {})
        XCTAssertTrue(SessionClipboard.writeLinked(png: png(), tiff: nil, text: "held", to: pb))
        paster.armLinked(png: png(), tiff: nil, transcript: "held", changeCount: pb.changeCount)
        XCTAssertTrue(paster.holdStagedLinked())
        XCTAssertTrue(paster.isAwaitingPaste)

        let other = PasteFollowUp(board: pb, poster: {})
        other.armLinked(png: png(), tiff: nil, transcript: "held", changeCount: pb.changeCount)
        pb.clearContents()
        pb.setString("something else", forType: .string)
        XCTAssertFalse(other.holdStagedLinked())
    }

    // MARK: Cost on the stop path (measured, logged)

    func testLinkedWriteCostIsSmall() {
        let big = png(2400, 1500)
        let tiff = NSImage(data: big)?.tiffRepresentation
        let pb = board()
        func time(_ body: () -> Void) -> Double {
            let start = CFAbsoluteTimeGetCurrent()
            for _ in 0..<5 { body() }
            return (CFAbsoluteTimeGetCurrent() - start) / 5 * 1000
        }
        let imageOnly = time { _ = SessionClipboard.writeImage(png: big, tiff: tiff, to: pb) }
        let linked = time { _ = SessionClipboard.writeLinked(png: big, tiff: tiff, text: "words", to: pb) }
        print("LINKED_COST writeImage=\(String(format: "%.2f", imageOnly))ms writeLinked=\(String(format: "%.2f", linked))ms png=\(big.count)B")
        XCTAssertLessThan(linked, imageOnly + 25)
    }
}
