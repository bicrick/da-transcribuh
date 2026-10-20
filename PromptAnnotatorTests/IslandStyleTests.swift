import XCTest
@testable import PromptAnnotator

final class IslandStyleTests: XCTestCase {
    func testStoredMiniBecomesCompact() {
        XCTAssertEqual(IslandStyle.stored("mini"), .compact)
        XCTAssertEqual(IslandStyle.stored("classic"), .classic)
        XCTAssertEqual(IslandStyle.stored("minimal"), .minimal)
        XCTAssertEqual(IslandStyle.stored(""), .classic)
    }
}
