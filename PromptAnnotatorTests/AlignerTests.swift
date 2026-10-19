import XCTest
@testable import PromptAnnotator

final class AlignerTests: XCTestCase {
    func testWordsSplitOnCommitInstantsAndClosingNote() {
        let words = [
            word("hello", 1, 1.4),
            word("there", 10, 10.4),
            word("next", 11, 11.4),
            word("tile", 30, 30.4),
            word("after", 31, 31.4),
            word("stop", 60, 60.3),
            word("late", 61, 61.2),
        ]

        let groups = Aligner.align(words: words, commitTimes: [10, 30], sessionEnd: 60)

        XCTAssertEqual(groups.count, 2)
        XCTAssertEqual(groups[0].words.map(\.text), ["hello", "there"])
        XCTAssertTrue(groups[0].closingNote.isEmpty)
        XCTAssertEqual(groups[1].words.map(\.text), ["next", "tile"])
        XCTAssertEqual(groups[1].closingNote.map(\.text), ["after", "stop"])
    }

    func testFirstGroupIncludesTheStartAndExactCommit() {
        let words = [word("zero", 0, 0.2), word("edge", 5, 5.2)]
        let groups = Aligner.align(words: words, commitTimes: [5], sessionEnd: 5)
        XCTAssertEqual(groups[0].words.map(\.text), ["zero", "edge"])
        XCTAssertTrue(groups[0].closingNote.isEmpty)
    }

    func testSpeechAfterTheOnlyCommitIsTheClosingNote() {
        let words = [word("later", 12, 12.4)]
        let groups = Aligner.align(words: words, commitTimes: [8], sessionEnd: 20)
        XCTAssertTrue(groups[0].words.isEmpty)
        XCTAssertEqual(groups[0].closingNote.map(\.text), ["later"])
    }

    func testEmptyWordsAndEmptyCommits() {
        let silent = Aligner.align(words: [], commitTimes: [4, 9], sessionEnd: 9)
        XCTAssertEqual(silent.count, 2)
        XCTAssertTrue(silent.allSatisfy { $0.words.isEmpty && $0.closingNote.isEmpty })
        XCTAssertTrue(Aligner.align(words: [word("hi", 1, 1.2)], commitTimes: [], sessionEnd: 2).isEmpty)
    }

    func testUnsortedWordsAreOrderedByStart() {
        let words = [word("b", 3, 3.2), word("a", 1, 1.2)]
        let groups = Aligner.align(words: words, commitTimes: [4], sessionEnd: 4)
        XCTAssertEqual(groups[0].words.map(\.text), ["a", "b"])
    }

    func testSpokenTextTrimsWhisperSpacing() {
        let text = Aligner.spokenText([
            word(" hello", 0, 0.2),
            word(" ", 0.2, 0.3),
            word("there", 0.3, 0.5),
        ])
        XCTAssertEqual(text, "hello there")
    }

    private func word(_ text: String, _ start: TimeInterval, _ end: TimeInterval) -> TimedWord {
        TimedWord(text: text, start: start, end: end)
    }
}
