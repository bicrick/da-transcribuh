import XCTest
@testable import PromptAnnotator

final class ContactSheetLayoutTests: XCTestCase {
    func testSingleImageScalesToTargetWidth() {
        let layout = SheetLayout.make(imageSizes: [CGSize(width: 2560, height: 1440)])
        XCTAssertEqual(layout.tiles.count, 1)
        XCTAssertEqual(layout.tiles[0].index, 1)
        XCTAssertEqual(layout.tiles[0].imageRect.width, 1280)
        XCTAssertEqual(layout.tiles[0].imageRect.height, 720)
        XCTAssertEqual(layout.canvasSize.width, 1280 + 72)
        XCTAssertEqual(layout.canvasSize.height, 36 + 56 + 720 + 36)
    }

    func testTwoTilesStackInCommitOrder() {
        let layout = SheetLayout.make(imageSizes: [
            CGSize(width: 1000, height: 500),
            CGSize(width: 2000, height: 1000),
        ])
        XCTAssertEqual(layout.tiles.map(\.index), [1, 2])
        XCTAssertEqual(layout.tiles[0].imageRect.height, 640)
        XCTAssertEqual(layout.tiles[1].imageRect.height, 640)
        XCTAssertEqual(layout.tiles[1].captionRect.minY, layout.tiles[0].imageRect.maxY + 28)
        XCTAssertEqual(layout.tiles[0].captionRect.minX, layout.tiles[1].imageRect.minX)
        XCTAssertEqual(layout.tiles[0].imageRect.width, layout.tiles[1].imageRect.width)
    }

    func testNarrowImageScalesUp() {
        let layout = SheetLayout.make(imageSizes: [CGSize(width: 640, height: 480)])
        XCTAssertEqual(layout.tiles[0].imageRect.size, CGSize(width: 1280, height: 960))
    }

    func testCaptionSitsOnTopOfTheImage() {
        let layout = SheetLayout.make(imageSizes: [CGSize(width: 1280, height: 720)])
        let tile = layout.tiles[0]
        XCTAssertEqual(tile.captionRect.maxY, tile.imageRect.minY)
        XCTAssertEqual(tile.captionRect.width, tile.imageRect.width)
        XCTAssertEqual(tile.captionRect.height, 56)
        XCTAssertEqual(tile.captionRect.minY, 36)
    }

    func testOddHeightRoundsToWholePixels() {
        let layout = SheetLayout.make(imageSizes: [CGSize(width: 1000, height: 333)])
        XCTAssertEqual(layout.tiles[0].imageRect.height, 426)
    }

    func testEmptyInputMakesNoCanvas() {
        let layout = SheetLayout.make(imageSizes: [])
        XCTAssertTrue(layout.tiles.isEmpty)
        XCTAssertEqual(layout.canvasSize, .zero)
    }

    func testFlippedRectUsesBottomLeftSpace() {
        let rect = CGRect(x: 10, y: 20, width: 30, height: 40)
        let flipped = SheetLayout.flipped(rect, canvasHeight: 100)
        XCTAssertEqual(flipped, CGRect(x: 10, y: 40, width: 30, height: 40))
    }
}
