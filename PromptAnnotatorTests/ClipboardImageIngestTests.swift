import AppKit
import XCTest
@testable import PromptAnnotator

@MainActor
final class ClipboardImageIngestTests: XCTestCase {
    private func board() -> NSPasteboard {
        NSPasteboard(name: .init("test.clip.png.\(UUID().uuidString)"))
    }

    private func samplePNG() -> Data {
        let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: 8, pixelsHigh: 6, bitsPerSample: 8,
            samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
            bytesPerRow: 0, bitsPerPixel: 0
        )!
        return rep.representation(using: .png, properties: [:])!
    }

    func testPNGOnTheBoardIsStoredByteForByte() {
        let pb = board()
        defer { pb.releaseGlobally() }
        let png = samplePNG()
        pb.clearContents()
        pb.setData(png, forType: .png)
        XCTAssertEqual(ClipboardWatcher.pngData(from: pb), png)
    }

    func testTIFFOnlyBoardIsConvertedToPNG() throws {
        let pb = board()
        defer { pb.releaseGlobally() }
        let tiff = try XCTUnwrap(NSBitmapImageRep(data: samplePNG())?.tiffRepresentation)
        pb.clearContents()
        pb.setData(tiff, forType: .tiff)
        let out = try XCTUnwrap(ClipboardWatcher.pngData(from: pb))
        XCTAssertTrue(out.starts(with: [0x89, 0x50, 0x4E, 0x47]))
        XCTAssertEqual(NSBitmapImageRep(data: out)?.pixelsWide, 8)
    }

    func testNonPNGBytesUnderThePNGTypeFallBackToDecode() {
        let pb = board()
        defer { pb.releaseGlobally() }
        pb.clearContents()
        pb.setData(Data("not a png".utf8), forType: .png)
        XCTAssertNil(ClipboardWatcher.pngData(from: pb))
    }
}
