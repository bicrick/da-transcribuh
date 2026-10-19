import XCTest
@testable import PromptAnnotator

final class ShapeRendererTests: XCTestCase {
    func testTinyClickIsNotAShape() {
        let click = AnnotationShape(
            id: UUID(),
            tool: .pen,
            color: .red,
            points: [CGPoint(x: 1, y: 1), CGPoint(x: 3, y: 2)],
            text: nil
        )
        XCTAssertFalse(click.isSignificant())

        let stroke = AnnotationShape(
            id: UUID(),
            tool: .pen,
            color: .red,
            points: [CGPoint(x: 0, y: 0), CGPoint(x: 10, y: 0)],
            text: nil
        )
        XCTAssertTrue(stroke.isSignificant())

        let blank = AnnotationShape(id: UUID(), tool: .text, color: .red, points: [.zero], text: "  ")
        XCTAssertFalse(blank.isSignificant())

        let label = AnnotationShape(id: UUID(), tool: .text, color: .red, points: [.zero], text: "Hi")
        XCTAssertTrue(label.isSignificant())
    }

    func testRectangleBakesIntoTheTopLeftOfTheBitmap() throws {
        // The stroke is 6pt with an 8pt halo, so the painted band is about 14pt wide.
        // Keep the rectangle near the top and well clear of the corners and the bottom.
        let base = solid(width: 160, height: 100, red: 0.45, green: 0.45, blue: 0.45)
        let shape = AnnotationShape(
            id: UUID(),
            tool: .rectangle,
            color: .red,
            points: [CGPoint(x: 40, y: 12), CGPoint(x: 90, y: 36)],
            text: nil
        )
        let image = try XCTUnwrap(
            ShapeRenderer.composite(base: base, shapes: [shape], pointSize: CGSize(width: 160, height: 100))
        )

        let onStroke = color(atX: 65, yFromTop: 12, image: image)
        XCTAssertGreaterThan(onStroke.r, 180, "The rectangle stroke should sit near the top of the bitmap")
        XCTAssertLessThan(onStroke.g, 90)
        XCTAssertLessThan(onStroke.b, 90)

        let outside = color(atX: 4, yFromTop: 4, image: image)
        XCTAssertGreaterThan(outside.r, 80)
        XCTAssertGreaterThan(outside.g, 80)
        XCTAssertLessThan(outside.r, 160)

        let bottom = color(atX: 65, yFromTop: 90, image: image)
        XCTAssertGreaterThan(bottom.g, 80, "A flipped composite would put the red stroke on the bottom edge")
        XCTAssertLessThan(bottom.r, 160)
    }

    func testSheetPaintsTheScaledImageUnderItsCaption() throws {
        let source = solid(width: 20, height: 10, red: 0.86, green: 0.1, blue: 0.1)
        let sheet = try XCTUnwrap(ContactSheet.render(images: [source], commitOffsets: [12]))
        let layout = SheetLayout.make(imageSizes: [CGSize(width: 20, height: 10)])
        XCTAssertEqual(sheet.width, Int(layout.canvasSize.width.rounded()))
        XCTAssertEqual(sheet.height, Int(layout.canvasSize.height.rounded()))

        let imageCenter = CGPoint(
            x: layout.tiles[0].imageRect.midX,
            y: layout.tiles[0].imageRect.midY
        )
        let painted = color(atX: Int(imageCenter.x), yFromTop: Int(imageCenter.y), image: sheet)
        XCTAssertGreaterThan(painted.r, 180)
        XCTAssertLessThan(painted.g, 80)

        let caption = color(atX: Int(layout.tiles[0].captionRect.midX), yFromTop: Int(layout.tiles[0].captionRect.midY), image: sheet)
        XCTAssertGreaterThan(caption.r, 230)
        XCTAssertGreaterThan(caption.g, 230)
        XCTAssertGreaterThan(caption.b, 230)
    }

    private func solid(width: Int, height: Int, red: CGFloat, green: CGFloat, blue: CGFloat) -> CGImage {
        let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.setFillColor(CGColor(srgbRed: red, green: green, blue: blue, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()!
    }

    private func color(atX x: Int, yFromTop: Int, image: CGImage) -> (r: UInt8, g: UInt8, b: UInt8) {
        var pixel = [UInt8](repeating: 0, count: 4)
        let context = CGContext(
            data: &pixel,
            width: 1,
            height: 1,
            bitsPerComponent: 8,
            bytesPerRow: 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.draw(
            image,
            in: CGRect(
                x: -CGFloat(x),
                y: -CGFloat((image.height - 1) - yFromTop),
                width: CGFloat(image.width),
                height: CGFloat(image.height)
            )
        )
        return (pixel[0], pixel[1], pixel[2])
    }
}
