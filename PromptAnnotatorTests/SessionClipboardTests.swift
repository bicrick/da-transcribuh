import AppKit
import XCTest
@testable import PromptAnnotator

final class SessionClipboardTests: XCTestCase {
    func testClipboardCarriesTheImageAndTheTranscript() throws {
        let context = CGContext(
            data: nil,
            width: 8,
            height: 8,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.setFillColor(CGColor(srgbRed: 0.8, green: 0.1, blue: 0.1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
        let image = NSImage(cgImage: context.makeImage()!, size: NSSize(width: 8, height: 8))
        let board = NSPasteboard(name: NSPasteboard.Name("PromptAnnotatorClipboardTest"))

        XCTAssertTrue(SessionClipboard.copy(image: image, transcript: "hello there", to: board))

        XCTAssertEqual(board.string(forType: .string), "hello there")
        let html = try XCTUnwrap(board.string(forType: .html))
        XCTAssertTrue(html.contains("data:image/png;base64,"))
        XCTAssertTrue(html.contains("hello there"))
        XCTAssertNotNil(board.data(forType: .png))

        let rtfd = try XCTUnwrap(board.data(forType: .rtfd))
        let pasted = try NSAttributedString(
            data: rtfd,
            options: [.documentType: NSAttributedString.DocumentType.rtfd],
            documentAttributes: nil
        )
        XCTAssertTrue(pasted.string.contains("hello there"))
        var foundImage = false
        pasted.enumerateAttribute(.attachment, in: NSRange(location: 0, length: pasted.length)) { value, _, _ in
            if value is NSTextAttachment {
                foundImage = true
            }
        }
        XCTAssertTrue(foundImage)
    }
}
