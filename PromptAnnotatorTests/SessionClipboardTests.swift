import AppKit
import XCTest
@testable import PromptAnnotator

final class SessionClipboardTests: XCTestCase {
    func testClipboardStagesTheLinkedTwoItemBoard() throws {
        let image = try redImage()
        let board = NSPasteboard(name: NSPasteboard.Name("PromptAnnotatorClipboardTest"))

        XCTAssertTrue(SessionClipboard.copy(image: image, transcript: "hello there", to: board))
        let items = try XCTUnwrap(board.pasteboardItems)
        XCTAssertEqual(items.count, 2)
        XCTAssertNotNil(items[0].data(forType: .png))
        XCTAssertNil(items[0].string(forType: .string))
        XCTAssertEqual(items[1].string(forType: .string), "hello there")

        XCTAssertTrue(SessionClipboard.writeTranscript("\nhello there", to: board))
        XCTAssertEqual(board.string(forType: .string), "\nhello there")
        XCTAssertNil(board.data(forType: .png))
    }

    func testClipboardStagesAnImageOnlyTakeByItself() throws {
        let image = try redImage()
        let board = NSPasteboard(name: NSPasteboard.Name("PromptAnnotatorClipboardImageOnlyTest"))
        XCTAssertTrue(SessionClipboard.copy(image: image, transcript: "  ", to: board))
        XCTAssertEqual(board.pasteboardItems?.count, 1)
        XCTAssertNotNil(board.data(forType: .png))
        XCTAssertNil(board.string(forType: .string))
    }

    func testCommandVIncludesShiftAndRejectsOtherModifiers() {
        let command = NSEvent.ModifierFlags.command
        let v = PasteKey.vKeyCode
        XCTAssertTrue(PasteKey.isCommandV(keyCode: v, modifiers: command, isRepeat: false))
        XCTAssertTrue(PasteKey.isCommandV(keyCode: v, modifiers: [command, .shift], isRepeat: false))
        XCTAssertFalse(PasteKey.isCommandV(keyCode: v, modifiers: command, isRepeat: true))
        XCTAssertFalse(PasteKey.isCommandV(keyCode: v, modifiers: [command, .option], isRepeat: false))
        XCTAssertFalse(PasteKey.isCommandV(keyCode: v, modifiers: [command, .control], isRepeat: false))
        XCTAssertFalse(PasteKey.isCommandV(keyCode: 0, modifiers: command, isRepeat: false))
    }

    private func redImage() throws -> NSImage {
        let context = try XCTUnwrap(CGContext(
            data: nil,
            width: 8,
            height: 8,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.setFillColor(CGColor(srgbRed: 0.8, green: 0.1, blue: 0.1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
        let cgImage = try XCTUnwrap(context.makeImage())
        return NSImage(cgImage: cgImage, size: NSSize(width: 8, height: 8))
    }
}
