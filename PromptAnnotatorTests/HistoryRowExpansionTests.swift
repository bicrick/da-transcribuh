import XCTest
@testable import PromptAnnotator

final class HistoryRowExpansionTests: XCTestCase {
    func testClickOpensARow() {
        XCTAssertEqual(HistoryRowExpansion.next(current: nil, tapped: "a"), "a")
    }

    func testClickingTheOpenRowCollapsesIt() {
        XCTAssertNil(HistoryRowExpansion.next(current: "a", tapped: "a"))
    }

    func testClickingAnotherRowMovesTheExpansion() {
        XCTAssertEqual(HistoryRowExpansion.next(current: "a", tapped: "b"), "b")
    }
}
