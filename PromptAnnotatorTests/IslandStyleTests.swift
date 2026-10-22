import XCTest
@testable import PromptAnnotator

final class IslandStyleTests: XCTestCase {
    func testStoredMiniBecomesCompactAndEmptyIsDefault() {
        XCTAssertEqual(IslandStyle.stored("mini"), .compact)
        XCTAssertEqual(IslandStyle.stored("classic"), .classic)
        XCTAssertEqual(IslandStyle.stored("minimal"), .minimal)
        XCTAssertEqual(IslandStyle.stored(""), .classic)
        XCTAssertEqual(IslandStyle.classic.title, "Default")
        XCTAssertEqual(IslandStyle.compact.title, "Compact")
    }
}
