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

    func testCommittedLabelUsesTheEditorGlyphOrigin() {
        let edit = TextEdit(origin: CGPoint(x: 10, y: 20), text: "Hi", color: .red)
        let shape = edit.shape()
        XCTAssertEqual(
            shape.points.first,
            CGPoint(x: 10 + InkStyle.textPadX, y: 20 + InkStyle.textPadY)
        )
        XCTAssertEqual(shape.text, "Hi")
        XCTAssertEqual(shape.tool, .text)
    }

    func testRectangleBakesIntoTheTopLeftOfTheBitmap() throws {
        // The stroke is 6pt of solid ink. Keep it near the top and clear of the corners.
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

    func testMarksAreSolidInkWithoutALightOutline() throws {
        let base = solid(width: 200, height: 140, red: 0.45, green: 0.45, blue: 0.45)
        let rectangle = AnnotationShape(
            id: UUID(),
            tool: .rectangle,
            color: .red,
            points: [CGPoint(x: 30, y: 18), CGPoint(x: 90, y: 48)],
            text: nil
        )
        let arrow = AnnotationShape(
            id: UUID(),
            tool: .arrow,
            color: .red,
            points: [CGPoint(x: 20, y: 80), CGPoint(x: 120, y: 80)],
            text: nil
        )
        let label = AnnotationShape(
            id: UUID(),
            tool: .text,
            color: .red,
            points: [CGPoint(x: 130, y: 18)],
            text: "Hi"
        )
        let pen = AnnotationShape(
            id: UUID(),
            tool: .pen,
            color: .red,
            points: [CGPoint(x: 16, y: 112), CGPoint(x: 100, y: 112)],
            text: nil
        )
        let image = try XCTUnwrap(
            ShapeRenderer.composite(
                base: base,
                shapes: [rectangle, arrow, label, pen],
                pointSize: CGSize(width: 200, height: 140)
            )
        )

        XCTAssertFalse(containsNearWhite(image), "Marks should be solid ink, with no white halo")

        let shaft = color(atX: 60, yFromTop: 80, image: image)
        XCTAssertGreaterThan(shaft.r, 180)
        XCTAssertLessThan(shaft.g, 80)
        // Six points off a 6pt shaft. The old halo reached about seven points from the center.
        assertBackground(color(atX: 60, yFromTop: 86, image: image))

        let head = color(atX: 112, yFromTop: 80, image: image)
        XCTAssertGreaterThan(head.r, 180, "The arrow head should be solid ink, not a light rim")
        XCTAssertLessThan(head.g, 90)

        let letter = reddest(
            image: image,
            xRange: 128..<170,
            yRange: 16..<48
        )
        XCTAssertGreaterThan(letter.r, 150, "The label should paint red glyphs")
        XCTAssertLessThan(letter.g, 100)
    }

    func testWhiteInkDoesNotGrowADarkOutline() throws {
        let base = solid(width: 120, height: 80, red: 0.45, green: 0.45, blue: 0.45)
        let shape = AnnotationShape(
            id: UUID(),
            tool: .rectangle,
            color: .white,
            points: [CGPoint(x: 20, y: 20), CGPoint(x: 80, y: 50)],
            text: nil
        )
        let image = try XCTUnwrap(
            ShapeRenderer.composite(base: base, shapes: [shape], pointSize: CGSize(width: 120, height: 80))
        )
        let onStroke = color(atX: 50, yFromTop: 20, image: image)
        XCTAssertGreaterThan(onStroke.r, 230)
        XCTAssertGreaterThan(onStroke.g, 230)
        // Six points outside a 6pt stroke. A dark halo used to darken this band.
        assertBackground(color(atX: 50, yFromTop: 26, image: image))
    }

    func testShortArrowStaysInFrontOfItsStart() throws {
        let base = solid(width: 120, height: 80, red: 0.45, green: 0.45, blue: 0.45)
        let shape = AnnotationShape(
            id: UUID(),
            tool: .arrow,
            color: .red,
            points: [CGPoint(x: 40, y: 40), CGPoint(x: 52, y: 40)],
            text: nil
        )
        let image = try XCTUnwrap(
            ShapeRenderer.composite(base: base, shapes: [shape], pointSize: CGSize(width: 120, height: 80))
        )
        assertBackground(color(atX: 34, yFromTop: 40, image: image))
        let tip = color(atX: 50, yFromTop: 40, image: image)
        XCTAssertGreaterThan(tip.r, 160)
        XCTAssertLessThan(tip.g, 100)
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

    func testSilentSheetPaintsTheImageWithoutACaption() throws {
        let source = solid(width: 20, height: 10, red: 0.86, green: 0.1, blue: 0.1)
        let sheet = try XCTUnwrap(
            ContactSheet.render(images: [source], commitOffsets: [1], showCaptions: false)
        )
        let layout = SheetLayout.make(imageSizes: [CGSize(width: 20, height: 10)], showCaptions: false)
        XCTAssertEqual(sheet.width, Int(layout.canvasSize.width.rounded()))
        XCTAssertEqual(sheet.height, Int(layout.canvasSize.height.rounded()))
        XCTAssertEqual(layout.canvasSize.height, 10 + 72)

        let imageCenter = CGPoint(
            x: layout.tiles[0].imageRect.midX,
            y: layout.tiles[0].imageRect.midY
        )
        let painted = color(atX: Int(imageCenter.x), yFromTop: Int(imageCenter.y), image: sheet)
        XCTAssertGreaterThan(painted.r, 180)
        XCTAssertLessThan(painted.g, 80)

        let above = color(atX: Int(imageCenter.x), yFromTop: 8, image: sheet)
        XCTAssertGreaterThan(above.r, 220)
        XCTAssertGreaterThan(above.g, 220)
        XCTAssertGreaterThan(above.b, 220)
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

    private func assertBackground(_ sample: (r: UInt8, g: UInt8, b: UInt8), file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertGreaterThan(sample.r, 90, file: file, line: line)
        XCTAssertLessThan(sample.r, 160, file: file, line: line)
        XCTAssertLessThan(abs(Int(sample.r) - Int(sample.g)), 18, file: file, line: line)
        XCTAssertLessThan(abs(Int(sample.g) - Int(sample.b)), 18, file: file, line: line)
    }

    private func containsNearWhite(_ image: CGImage) -> Bool {
        let width = image.width
        let height = image.height
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        let painted = bytes.withUnsafeMutableBytes { raw -> Bool in
            guard let context = CGContext(
                data: raw.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else {
                return false
            }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard painted else { return false }
        for y in 0..<height {
            for x in 0..<width {
                let row = height - 1 - y
                let index = (row * width + x) * 4
                let red = bytes[index]
                let green = bytes[index + 1]
                let blue = bytes[index + 2]
                if red > 230, green > 230, blue > 230 {
                    return true
                }
            }
        }
        return false
    }

    private func reddest(
        image: CGImage,
        xRange: Range<Int>,
        yRange: Range<Int>
    ) -> (r: UInt8, g: UInt8, b: UInt8) {
        var best = (r: UInt8(0), g: UInt8(0), b: UInt8(0))
        var bestScore = Int.min
        for y in yRange {
            for x in xRange {
                let sample = color(atX: x, yFromTop: y, image: image)
                let score = Int(sample.r) - Int(sample.g) - Int(sample.b)
                if score > bestScore {
                    bestScore = score
                    best = sample
                }
            }
        }
        return best
    }
}
