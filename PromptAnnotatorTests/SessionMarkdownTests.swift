import XCTest
@testable import PromptAnnotator

final class SessionMarkdownTests: XCTestCase {
    func testSectionsImagesAndClosingNote() {
        let notes = SessionMarkdown.render(
            started: "2026-10-19 17:14:02",
            ended: "2026-10-19 17:16:40",
            model: "small.en_217MB",
            sections: [
                SessionMarkdown.Section(
                    index: 1,
                    commitOffset: 12,
                    imagePath: "frames/01.png",
                    words: [
                        TimedWord(text: " hello", start: 1, end: 1.4),
                        TimedWord(text: "there", start: 1.5, end: 2),
                    ],
                    closingNote: []
                ),
                SessionMarkdown.Section(
                    index: 2,
                    commitOffset: 40,
                    imagePath: "frames/02.png",
                    words: [
                        TimedWord(text: "is", start: 15, end: 15.2),
                        TimedWord(text: " too", start: 16, end: 16.2),
                        TimedWord(text: "close", start: 17, end: 17.4),
                    ],
                    closingNote: [
                        TimedWord(text: "and", start: 50, end: 50.2),
                        TimedWord(text: " the", start: 51, end: 51.2),
                        TimedWord(text: "label", start: 52, end: 52.4),
                    ]
                ),
            ],
            transcript: [
                TimedWord(text: " hello", start: 1, end: 1.4),
                TimedWord(text: "there", start: 1.5, end: 2),
                TimedWord(text: "is", start: 15, end: 15.2),
                TimedWord(text: " too", start: 16, end: 16.2),
                TimedWord(text: "close", start: 17, end: 17.4),
                TimedWord(text: "and", start: 50, end: 50.2),
                TimedWord(text: " the", start: 51, end: 51.2),
                TimedWord(text: "label", start: 52, end: 52.4),
            ],
            transcriptionError: nil
        )

        let parts = notes.components(separatedBy: "## Transcript")
        XCTAssertEqual(parts.count, 2)
        XCTAssertTrue(parts[0].contains("## 1 · 0:12"))
        XCTAssertTrue(parts[0].contains("![1](frames/01.png)"))
        XCTAssertTrue(parts[0].contains("hello there"))
        XCTAssertTrue(parts[0].contains("## 2 · 0:40"))
        XCTAssertTrue(parts[0].contains("![2](frames/02.png)"))
        XCTAssertTrue(parts[0].contains("is too close"))
        XCTAssertEqual(parts[0].components(separatedBy: "Closing note:").count, 2)
        XCTAssertTrue(parts[0].contains("and the label"))
        XCTAssertTrue(parts[0].contains("Model: small.en_217MB"))
        XCTAssertFalse(parts[0].components(separatedBy: "## 2").first?.contains("Closing note:") ?? true)

        XCTAssertTrue(parts[1].contains("[0:01.00] hello"))
        XCTAssertTrue(parts[1].contains("[0:01.50] there"))
        XCTAssertTrue(parts[1].contains("[0:50.00] and"))
        XCTAssertTrue(parts[1].contains("[0:52.00] label"))
    }

    func testMissingTranscriptIsExplicit() {
        let notes = SessionMarkdown.render(
            started: "start",
            ended: "end",
            model: nil,
            sections: [],
            transcript: [],
            transcriptionError: "model unavailable"
        )
        XCTAssertTrue(notes.contains("Transcription failed: model unavailable"))
        XCTAssertTrue(notes.contains("No speech detected."))
    }

    func testPasteTextGroupsTilesAndClosingNote() {
        let text = SessionMarkdown.pasteText(
            sections: [
                SessionMarkdown.Section(
                    index: 1,
                    commitOffset: 12,
                    imagePath: "frames/01.png",
                    words: [
                        TimedWord(text: "hello", start: 1, end: 1.4),
                        TimedWord(text: "there", start: 1.5, end: 2),
                    ],
                    closingNote: []
                ),
                SessionMarkdown.Section(
                    index: 2,
                    commitOffset: 40,
                    imagePath: "frames/02.png",
                    words: [TimedWord(text: "next", start: 15, end: 15.4)],
                    closingNote: [TimedWord(text: "done", start: 50, end: 50.2)]
                ),
            ],
            transcript: [],
            transcriptionError: nil
        )
        XCTAssertEqual(text, "hello there\n\nnext done")
    }
}
