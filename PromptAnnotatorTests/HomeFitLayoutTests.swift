import XCTest
@testable import PromptAnnotator

final class HomeFitLayoutTests: XCTestCase {
    func testRowsThatFitFloorsToWholeRows() {
        XCTAssertEqual(HomeFitLayout.recentRowsThatFit(height: 239), 5)
        XCTAssertEqual(HomeFitLayout.recentRowsThatFit(height: 240), 6)
    }

    func testRowsThatFitClampsToOneAndMax() {
        XCTAssertEqual(HomeFitLayout.recentRowsThatFit(height: 0), 1)
        XCTAssertEqual(HomeFitLayout.recentRowsThatFit(height: .infinity), 1)
        XCTAssertEqual(HomeFitLayout.recentRowsThatFit(height: 10_000), HomeFitLayout.recentMax)
    }

    func testRowHeightStretchesOnlyWhenListFillsCell() {
        // 5 rows fit in 230pt; with enough sessions they share it (46pt each).
        XCTAssertEqual(HomeFitLayout.recentRowHeight(height: 230, fit: 5, available: 9), 46)
        // Fewer sessions than slots: keep the natural row height.
        XCTAssertEqual(HomeFitLayout.recentRowHeight(height: 230, fit: 5, available: 3), HomeFitLayout.recentRowHeight)
    }
}
