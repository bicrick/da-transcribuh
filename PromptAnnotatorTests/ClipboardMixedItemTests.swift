import AppKit
import SwiftUI
import XCTest
@testable import PromptAnnotator

/// Mixed copies (text + image in one copy): capture, storage, migration, paste-back.
@MainActor
final class ClipboardMixedItemTests: XCTestCase {
    private var folder: URL!
    private var store: ClipboardHistoryStore!
    private var boards: [NSPasteboard] = []

    override func setUp() async throws {
        folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("clipboard-mixed-\(UUID().uuidString)", isDirectory: true)
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
        let pb = NSPasteboard(name: .init("test.clip.mixed.\(UUID().uuidString)"))
        pb.clearContents()
        boards.append(pb)
        return pb
    }

    private func png(_ w: Int = 12, _ h: Int = 8) -> Data {
        let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: w, pixelsHigh: h, bitsPerSample: 8,
            samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
            bytesPerRow: 0, bitsPerPixel: 0
        )!
        return rep.representation(using: .png, properties: [:])!
    }

    private func payload(_ pb: NSPasteboard, images: Bool = true, text: Bool = true) -> ClipboardCapturePayload? {
        ClipboardCapture.payload(from: pb, saveFiles: true, saveImages: images, saveText: text)
    }

    // MARK: Capture

    func testTextAndPNGOnOneBoardIsOneMixedPayload() {
        let pb = board()
        let image = png()
        let item = NSPasteboardItem()
        item.setData(image, forType: .png)
        item.setString("  hello from Safari \n", forType: .string)
        pb.writeObjects([item])
        XCTAssertEqual(payload(pb), .mixed(text: "hello from Safari", png: image))
    }

    func testImageOnlyAndTextOnlyBoardsAreUnchanged() {
        let a = board()
        let image = png()
        a.setData(image, forType: .png)
        XCTAssertEqual(payload(a), .image(png: image))

        let b = board()
        b.setString("just words", forType: .string)
        XCTAssertEqual(payload(b), .text("just words"))
    }

    func testTextWithOnlyAPDFRenderingStaysText() throws {
        // Pages and Keynote add a PDF of the selected words. That used to be
        // stored as a picture and the text was dropped.
        let view = NSView(frame: NSRect(x: 0, y: 0, width: 40, height: 20))
        let pdf = view.dataWithPDF(inside: view.bounds)
        let pb = board()
        let item = NSPasteboardItem()
        item.setData(pdf, forType: .pdf)
        item.setString("slide title", forType: .string)
        pb.writeObjects([item])
        XCTAssertEqual(payload(pb), .text("slide title"))
    }

    func testRTFDWithAttachedImageIsMixed() throws {
        let image = try XCTUnwrap(NSImage(data: png(10, 10)))
        let rtfd = try XCTUnwrap(SessionClipboard.rtfdData(image: image, text: "caption under the picture"))
        let pb = board()
        pb.setData(rtfd, forType: .rtfd)
        guard case let .mixed(text, data)? = payload(pb) else {
            return XCTFail("expected mixed, got \(String(describing: payload(pb)))")
        }
        XCTAssertEqual(text, "caption under the picture")
        XCTAssertFalse(text.contains("\u{FFFC}"))
        XCTAssertEqual(NSBitmapImageRep(data: data)?.pixelsWide, 10)
    }

    func testSettingsPickOneSideOfAMixedBoard() {
        let pb = board()
        let image = png()
        let item = NSPasteboardItem()
        item.setData(image, forType: .png)
        item.setString("both", forType: .string)
        pb.writeObjects([item])
        XCTAssertEqual(payload(pb, images: false), .text("both"))
        XCTAssertEqual(payload(pb, text: false), .image(png: image))
        XCTAssertNil(payload(pb, images: false, text: false))
    }

    func testFilesStillWinOverImageAndText() {
        let pb = board()
        let url = folder.appendingPathComponent("a.txt")
        FileManager.default.createFile(atPath: url.path, contents: Data("x".utf8))
        pb.writeObjects([url as NSURL])
        XCTAssertEqual(payload(pb), .files([url.path]))
    }

    // MARK: Storage and migration

    func testMixedItemStoresBothAndSurvivesReload() throws {
        let image = png()
        let stored = try XCTUnwrap(store.ingest(
            payload: .mixed(text: "notes line", png: image), source: .pasteboard, applicationName: "Notes"
        ))
        XCTAssertTrue(stored.isMixed)
        XCTAssertTrue(stored.hasImage)
        XCTAssertEqual(stored.kind, .text)
        XCTAssertEqual(stored.previewLine, "notes line")
        XCTAssertEqual(store.imagePNGData(for: stored), image)
        XCTAssertEqual(stored.imageWidth, 12)

        ClipboardHistoryStore.flushPendingWrites()
        let reloaded = ClipboardHistoryStore(folder: folder)
        let item = try XCTUnwrap(reloaded.items.first)
        XCTAssertTrue(item.isMixed)
        XCTAssertEqual(item.text, "notes line")
        XCTAssertEqual(reloaded.imagePNGData(for: item), image)
    }

    func testMixedDedupeIsSeparateFromTextOnly() {
        let image = png()
        store.ingest(payload: .mixed(text: "same", png: image), source: .pasteboard, applicationName: nil)
        store.ingest(payload: .mixed(text: "same", png: image), source: .pasteboard, applicationName: nil)
        XCTAssertEqual(store.items.count, 1)
        XCTAssertEqual(store.items.first?.copyCount, 2)
        store.ingest(payload: .text("same"), source: .pasteboard, applicationName: nil)
        XCTAssertEqual(store.items.count, 2)
        XCTAssertFalse(store.items[0].isMixed)
        XCTAssertTrue(store.items[1].isMixed)
    }

    func testLegacyIndexStillLoads() throws {
        // An index written before mixed items existed (no new fields, one type each).
        let legacy = """
        [
          {"id":"5C0E2B4A-0A3B-4D7E-9E51-1D2C3B4A5F60","createdAt":"2026-10-01T12:00:00Z",
           "kind":"text","source":"pasteboard","text":"old text","pinned":false,
           "fingerprint":"text:abc"},
          {"id":"7D1F3C5B-1B4C-4E8F-8F62-2E3D4C5B6A71","createdAt":"2026-10-01T11:00:00Z",
           "kind":"image","source":"screenshot","imageFileName":"old.png","pinned":true,
           "fingerprint":"image:def","imageWidth":12,"imageHeight":8}
        ]
        """
        let legacyFolder = folder.appendingPathComponent("legacy", isDirectory: true)
        try FileManager.default.createDirectory(
            at: legacyFolder.appendingPathComponent("images"), withIntermediateDirectories: true
        )
        try Data(legacy.utf8).write(to: legacyFolder.appendingPathComponent("index.json"))
        try png().write(to: legacyFolder.appendingPathComponent("images/old.png"))
        let old = ClipboardHistoryStore(folder: legacyFolder)
        XCTAssertEqual(old.items.count, 2)
        let text = try XCTUnwrap(old.items.first { $0.kind == .text })
        let image = try XCTUnwrap(old.items.first { $0.kind == .image })
        XCTAssertFalse(text.isMixed)
        XCTAssertFalse(text.hasImage)
        XCTAssertFalse(image.isMixed)
        XCTAssertTrue(image.hasImage)
        XCTAssertEqual(text.copyCount, 1)
        XCTAssertNotNil(old.image(for: image))
    }

    // MARK: Paste-back

    func testMixedPasteBackWritesImageAndTextTogether() throws {
        let image = png()
        let item = try XCTUnwrap(store.ingest(
            payload: .mixed(text: "pasted words", png: image), source: .pasteboard, applicationName: nil
        ))
        let pb = board()
        XCTAssertTrue(ClipboardHistoryController.write(item, store: store, plainOnly: true, to: pb))
        let types = pb.types ?? []
        XCTAssertTrue(types.contains(.png))
        XCTAssertTrue(types.contains(.tiff))
        XCTAssertTrue(types.contains(.string))
        XCTAssertFalse(types.contains(.rtfd))
        XCTAssertEqual(pb.string(forType: .string), "pasted words")
        XCTAssertEqual(pb.data(forType: .png), image)
        XCTAssertEqual(pb.pasteboardItems?.count, 1)
        // What we write is captured back as the same mixed item.
        XCTAssertEqual(payload(pb), .mixed(text: "pasted words", png: image))
    }

    func testMixedPasteBackWithFormattingAddsRTFD() throws {
        let item = try XCTUnwrap(store.ingest(
            payload: .mixed(text: "rich", png: png()), source: .pasteboard, applicationName: nil
        ))
        let pb = board()
        XCTAssertTrue(ClipboardHistoryController.write(item, store: store, plainOnly: false, to: pb))
        XCTAssertTrue((pb.types ?? []).contains(.rtfd))
        XCTAssertEqual(pb.string(forType: .string), "rich")
    }

    func testImagePasteBackUsesStoredBytes() throws {
        let image = png()
        let item = try XCTUnwrap(store.ingest(payload: .image(png: image), source: .pasteboard, applicationName: nil))
        let pb = board()
        XCTAssertTrue(ClipboardHistoryController.write(item, store: store, plainOnly: true, to: pb))
        XCTAssertEqual(pb.data(forType: .png), image)
        XCTAssertNil(pb.string(forType: .string))
    }

    // MARK: Preview sizing (root cause of the cropped image preview)

    func testImagePreviewMeasuresTheImage() throws {
        let image = PerfSuite.syntheticPNG(width: 1200, height: 760, seed: 1)
        let item = try XCTUnwrap(store.ingest(payload: .image(png: image), source: .pasteboard, applicationName: nil))
        let nsImage = try XCTUnwrap(store.image(for: item))
        let fitted = ClipboardPreviewLayout.fit(nsImage.size, in: CGSize(
            width: ClipboardPreviewPopover.contentWidth, height: ClipboardPreviewPopover.imageMaxHeight
        ))
        let host = NSHostingView(rootView: ClipboardPreviewPopover(item: item, image: nsImage))
        // The old layout measured only the meta rows (~160pt), so the window was
        // too short and the picture and both horizontal borders were cut off.
        XCTAssertGreaterThan(host.fittingSize.height, fitted.height + 100)
    }

    func testPreviewWindowResizesToEachItem() throws {
        // Root cause: the window was sized from its own hosting view, which reports
        // the size it already has, so every preview stayed at the first size.
        let small = try XCTUnwrap(store.ingest(payload: .text("short"), source: .pasteboard, applicationName: nil))
        let picture = try XCTUnwrap(store.ingest(
            payload: .image(png: PerfSuite.syntheticPNG(width: 1200, height: 760, seed: 2)),
            source: .pasteboard, applicationName: nil
        ))
        let preview = ClipboardPreviewPanelController()
        defer { preview.hide(animated: false) }
        let list = NSRect(x: 200, y: 200, width: 450, height: 480)
        preview.show(item: small, image: nil, beside: list)
        let shortHeight = try XCTUnwrap(preview.window?.frame.height)
        preview.show(item: picture, image: store.image(for: picture), beside: list)
        let imageHeight = try XCTUnwrap(preview.window?.frame.height)
        XCTAssertGreaterThan(imageHeight, shortHeight + 100)
        XCTAssertEqual(preview.window?.contentView?.frame.height, imageHeight)
    }

    func testSwapDuringTheOpenSlideKeepsTheNewSize() throws {
        let picture = try XCTUnwrap(store.ingest(
            payload: .image(png: PerfSuite.syntheticPNG(width: 1200, height: 760, seed: 4)),
            source: .pasteboard, applicationName: nil
        ))
        let small = try XCTUnwrap(store.ingest(payload: .text("short"), source: .pasteboard, applicationName: nil))
        let preview = ClipboardPreviewPanelController()
        defer { preview.hide(animated: false) }
        let list = NSRect(x: 200, y: 200, width: 450, height: 480)
        preview.show(item: picture, image: store.image(for: picture), beside: list)
        // Swap at once, while the open slide is still running.
        preview.show(item: small, image: nil, beside: list)
        let settle = expectation(description: "slide finished")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { settle.fulfill() }
        wait(for: [settle], timeout: 2)
        let alone = ClipboardPreviewPanelController()
        defer { alone.hide(animated: false) }
        alone.show(item: small, image: nil, beside: list)
        let expected = try XCTUnwrap(alone.window?.frame.height)
        XCTAssertEqual(try XCTUnwrap(preview.window?.frame.height), expected, accuracy: 0.5)
    }

    func testPinnedCardHeightFillsTheWindowExactly() throws {
        let long = String(repeating: "a long line of copied text\n", count: 200)
        let item = try XCTUnwrap(store.ingest(payload: .text(long), source: .pasteboard, applicationName: nil))
        let free = NSHostingView(rootView: ClipboardPreviewPopover(item: item, image: nil))
        let height = ClipboardPreviewLayout.cardHeight(measured: free.fittingSize.height)
        XCTAssertLessThanOrEqual(height, ClipboardPreviewPopover.maxHeight)
        let pinned = NSHostingView(rootView: ClipboardPreviewPopover(item: item, image: nil, height: height))
        XCTAssertEqual(pinned.fittingSize.width, ClipboardPreviewPopover.width + Ink.bevelOffset, accuracy: 0.5)
        XCTAssertEqual(pinned.fittingSize.height, height + Ink.bevelOffset, accuracy: 0.5)
    }
}

final class ClipboardPreviewLayoutTests: XCTestCase {
    private let box = CGSize(width: 296, height: 240)

    func testLandscapeIsWidthBound() {
        XCTAssertEqual(ClipboardPreviewLayout.fit(CGSize(width: 1200, height: 760), in: box),
                       CGSize(width: 296, height: 187))
    }

    func testPortraitIsHeightBound() {
        XCTAssertEqual(ClipboardPreviewLayout.fit(CGSize(width: 900, height: 1600), in: box),
                       CGSize(width: 135, height: 240))
    }

    func testSmallImagesAreNotUpscaled() {
        XCTAssertEqual(ClipboardPreviewLayout.fit(CGSize(width: 16, height: 16), in: box),
                       CGSize(width: 16, height: 16))
    }

    func testDegenerateSizesFitToZero() {
        XCTAssertEqual(ClipboardPreviewLayout.fit(.zero, in: box), .zero)
        XCTAssertEqual(ClipboardPreviewLayout.fit(CGSize(width: 10, height: 0), in: box), .zero)
    }

    func testCardHeightIsCapped() {
        XCTAssertEqual(ClipboardPreviewLayout.cardHeight(measured: 20), ClipboardPreviewPopover.minHeight)
        XCTAssertEqual(ClipboardPreviewLayout.cardHeight(measured: 300.2), 301)
        XCTAssertEqual(ClipboardPreviewLayout.cardHeight(measured: 4000), ClipboardPreviewPopover.maxHeight)
    }
}

/// Every open lands at the top with the search field focused.
@MainActor
final class ClipboardPanelOpenResetTests: XCTestCase {
    private final class FlippedView: NSView {
        override var isFlipped: Bool { true }
    }

    private func scrollView(flipped: Bool) -> NSScrollView {
        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 100, height: 100))
        let doc: NSView = flipped ? FlippedView() : NSView()
        doc.frame = NSRect(x: 0, y: 0, width: 100, height: 500)
        scroll.documentView = doc
        scroll.contentView.setBoundsOrigin(NSPoint(x: 0, y: 200))
        return scroll
    }

    func testScrollToTopOnFlippedDocument() {
        let scroll = scrollView(flipped: true)
        ClipboardHistoryPanelController.scrollToTop(scroll)
        XCTAssertEqual(scroll.contentView.bounds.origin.y, 0)
    }

    func testScrollToTopOnUnflippedDocument() {
        let scroll = scrollView(flipped: false)
        ClipboardHistoryPanelController.scrollToTop(scroll)
        XCTAssertEqual(scroll.contentView.bounds.origin.y, 400)
    }

    func testFindsTheEditableSearchFieldNotLabels() {
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 200, height: 100))
        let label = NSTextField(labelWithString: "clipboard")
        let nested = NSView()
        let field = NSTextField(string: "")
        root.addSubview(label)
        root.addSubview(nested)
        nested.addSubview(field)
        XCTAssertTrue(ClipboardHistoryPanelController.firstEditableTextField(in: root) === field)
    }

    func testFocusPutsTheFieldEditorOnTheSearchField() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 200, height: 100),
                              styleMask: [.titled], backing: .buffered, defer: false)
        defer { window.close() }
        window.isReleasedWhenClosed = false
        let root = NSView(frame: window.contentLayoutRect)
        let field = NSTextField(frame: NSRect(x: 10, y: 10, width: 120, height: 22))
        root.addSubview(field)
        window.contentView = root
        window.makeFirstResponder(root)
        ClipboardHistoryPanelController.focusSearchField(in: window, root: root)
        let editor = window.firstResponder as? NSTextView
        XCTAssertTrue(editor?.delegate === field)
    }
}
