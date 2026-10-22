import XCTest
@testable import PromptAnnotator

final class DTScrollGeometryTests: XCTestCase {
    func testThumbTravelsTopMidBottom() {
        let geoBase = DTScrollGeometry(contentHeight: 1000, viewportHeight: 280, offset: 0)
        let trackH: CGFloat = 260
        let minH: CGFloat = 24
        let thumbH = geoBase.thumbHeight(trackH: trackH, minH: minH)
        XCTAssertGreaterThan(thumbH, minH - 0.1)
        XCTAssertLessThan(thumbH, trackH)

        let top = DTScrollGeometry(contentHeight: 1000, viewportHeight: 280, offset: 0)
        XCTAssertEqual(top.thumbY(trackH: trackH, minH: minH), 0, accuracy: 0.01)

        let scrollable = top.scrollable
        let mid = DTScrollGeometry(contentHeight: 1000, viewportHeight: 280, offset: scrollable * 0.45)
        let bottom = DTScrollGeometry(contentHeight: 1000, viewportHeight: 280, offset: scrollable)

        let midY = mid.thumbY(trackH: trackH, minH: minH)
        let bottomY = bottom.thumbY(trackH: trackH, minH: minH)
        let travel = trackH - thumbH
        XCTAssertEqual(midY, 0.45 * travel, accuracy: 0.5)
        XCTAssertEqual(bottomY, travel, accuracy: 0.5)
        XCTAssertGreaterThan(midY, top.thumbY(trackH: trackH, minH: minH))
        XCTAssertGreaterThan(bottomY, midY)
    }

    func testCollapsedContentHidesScroller() {
        let geo = DTScrollGeometry(contentHeight: 280, viewportHeight: 280, offset: 0)
        XCTAssertFalse(geo.needsScroller)
        XCTAssertEqual(geo.scrollable, 0)
        XCTAssertEqual(geo.thumbY(trackH: 260, minH: 24), 0)
    }

    func testContentTallerThanViewportNeedsScroller() {
        let geo = DTScrollGeometry(contentHeight: 900, viewportHeight: 280, offset: 40)
        XCTAssertTrue(geo.needsScroller)
        XCTAssertEqual(geo.scrollable, 620)
    }

    func testFlippedClipOffset() {
        let geo = DTScrollGeometry.fromFlippedClip(
            contentHeight: 800,
            viewportHeight: 200,
            originY: 150
        )
        XCTAssertEqual(geo.offset, 150)
    }
}
