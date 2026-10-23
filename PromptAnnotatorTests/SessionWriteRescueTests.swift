import XCTest
@testable import PromptAnnotator

final class SessionWriteRescueTests: XCTestCase {
    func testRescuedTextKeepsSpokenWords() {
        let words = [
            TimedWord(text: " hello", start: 0, end: 0.2),
            TimedWord(text: " world", start: 0.3, end: 0.5),
        ]
        XCTAssertEqual(SessionWriter.rescuedPasteText(words: words), Aligner.spokenText(words).trimmingCharacters(in: .whitespacesAndNewlines))
        XCTAssertFalse(SessionWriter.rescuedPasteText(words: words).isEmpty)
    }

    func testRescuedTextEmptyWithoutWords() {
        XCTAssertEqual(SessionWriter.rescuedPasteText(words: []), "")
    }
}
