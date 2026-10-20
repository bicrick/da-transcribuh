import CoreGraphics
import XCTest
@testable import PromptAnnotator

final class CaptureTests: XCTestCase {
    func testShortPressIsNotADrag() {
        let start = CGPoint(x: 10, y: 10)
        let end = CGPoint(x: 14, y: 13)
        XCTAssertFalse(CaptureGesture.isDrag(from: start, to: end))
        XCTAssertEqual(CaptureGesture.distance(from: start, to: end), 5, accuracy: 0.01)
    }

    func testMovementPastTheThresholdIsADrag() {
        let start = CGPoint(x: 10, y: 10)
        let end = CGPoint(x: 16, y: 10)
        XCTAssertTrue(CaptureGesture.isDrag(from: start, to: end))
    }

    func testRectNormalizesADragTowardTheOrigin() {
        let rect = CaptureGesture.rect(from: CGPoint(x: 80, y: 50), to: CGPoint(x: 20, y: 10))
        XCTAssertEqual(rect, CGRect(x: 20, y: 10, width: 60, height: 40))
    }

    func testThinLineIsNotASnippet() {
        let rect = CaptureGesture.rect(from: CGPoint(x: 0, y: 0), to: CGPoint(x: 40, y: 2))
        XCTAssertFalse(CaptureGesture.isCapturable(rect))
    }

    func testBoxPastTheMinimumIsASnippet() {
        let rect = CaptureGesture.rect(from: CGPoint(x: 4, y: 4), to: CGPoint(x: 30, y: 18))
        XCTAssertTrue(CaptureGesture.isCapturable(rect))
    }

    func testPixelRectScalesPointsToPixels() {
        let pixel = RegionCrop.pixelRect(
            selection: CGRect(x: 10, y: 5, width: 20, height: 10),
            pointSize: CGSize(width: 50, height: 25),
            pixelSize: CGSize(width: 100, height: 50)
        )
        XCTAssertEqual(pixel, CGRect(x: 20, y: 10, width: 40, height: 20))
    }

    func testPixelRectClampsToTheDisplay() {
        let pixel = RegionCrop.pixelRect(
            selection: CGRect(x: 80, y: 40, width: 40, height: 30),
            pointSize: CGSize(width: 100, height: 50),
            pixelSize: CGSize(width: 100, height: 50)
        )
        XCTAssertEqual(pixel, CGRect(x: 80, y: 40, width: 20, height: 10))
    }

    func testEmptySelectionDoesNotCrop() {
        let pixel = RegionCrop.pixelRect(
            selection: CGRect(x: 10, y: 10, width: 0, height: 12),
            pointSize: CGSize(width: 100, height: 100),
            pixelSize: CGSize(width: 100, height: 100)
        )
        XCTAssertNil(pixel)
    }

    func testCropKeepsTheTopOfTheDisplay() throws {
        let image = try XCTUnwrap(sampleImage(width: 20, height: 20))
        let top = try XCTUnwrap(
            RegionCrop.crop(image, selection: CGRect(x: 0, y: 0, width: 20, height: 1), pointSize: CGSize(width: 20, height: 20))
        )
        let bottom = try XCTUnwrap(
            RegionCrop.crop(image, selection: CGRect(x: 0, y: 19, width: 20, height: 1), pointSize: CGSize(width: 20, height: 20))
        )
        XCTAssertEqual(top.width, 20)
        XCTAssertEqual(top.height, 1)
        XCTAssertEqual(bottom.height, 1)
        let topPixel = try XCTUnwrap(firstPixel(top))
        let bottomPixel = try XCTUnwrap(firstPixel(bottom))
        XCTAssertGreaterThan(topPixel.red, 200)
        XCTAssertLessThan(topPixel.blue, 40)
        XCTAssertGreaterThan(bottomPixel.blue, 200)
        XCTAssertLessThan(bottomPixel.red, 40)
    }

    /// Red along the visual top row, blue everywhere else. Context origin is bottom-left.
    private func sampleImage(width: Int, height: Int) -> CGImage? {
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }
        context.setFillColor(CGColor(red: 0, green: 0, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: height - 1, width: width, height: 1))
        return context.makeImage()
    }

    private func firstPixel(_ image: CGImage) -> (red: UInt8, green: UInt8, blue: UInt8)? {
        var pixel = [UInt8](repeating: 0, count: 4)
        guard let context = CGContext(
            data: &pixel,
            width: 1,
            height: 1,
            bitsPerComponent: 8,
            bytesPerRow: 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }
        context.draw(image, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        return (pixel[0], pixel[1], pixel[2])
    }
}
