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

        XCTAssertTrue(notes.contains("## 1 · 0:12"))
        XCTAssertTrue(notes.contains("![1](frames/01.png)"))
        XCTAssertTrue(notes.contains("hello there"))
        XCTAssertTrue(notes.contains("## 2 · 0:40"))
        XCTAssertTrue(notes.contains("![2](frames/02.png)"))
        XCTAssertTrue(notes.contains("is too close"))
        XCTAssertEqual(notes.components(separatedBy: "Closing note:").count, 2)
        XCTAssertTrue(notes.contains("and the label"))
        XCTAssertTrue(notes.contains("Model: small.en_217MB"))
        XCTAssertFalse(notes.components(separatedBy: "## 2").first?.contains("Closing note:") ?? true)
        XCTAssertFalse(notes.contains("## Transcript"))
        XCTAssertFalse(notes.contains("[0:01.00]"))
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
        XCTAssertFalse(notes.contains("No speech detected."))
        XCTAssertFalse(notes.contains("## Transcript"))
    }

    func testSilentCapturesAreImagesOnly() {
        let notes = SessionMarkdown.render(
            started: "2026-10-20 09:30:36",
            ended: "2026-10-20 09:30:39",
            model: nil,
            sections: [
                SessionMarkdown.Section(
                    index: 1,
                    commitOffset: 1,
                    imagePath: "frames/01.png",
                    words: [],
                    closingNote: []
                ),
                SessionMarkdown.Section(
                    index: 2,
                    commitOffset: 4,
                    imagePath: "frames/02.png",
                    words: [],
                    closingNote: []
                ),
            ],
            transcript: [],
            transcriptionError: nil
        )
        XCTAssertTrue(notes.contains("![1](frames/01.png)"))
        XCTAssertTrue(notes.contains("![2](frames/02.png)"))
        XCTAssertFalse(notes.contains("## "))
        XCTAssertFalse(notes.contains("Transcript"))
        XCTAssertFalse(notes.contains("No speech detected"))
        XCTAssertFalse(notes.contains("0:01"))
    }

    func testTimestampOnlyMarksASpokenTile() {
        let notes = SessionMarkdown.render(
            started: "start",
            ended: "end",
            model: nil,
            sections: [
                SessionMarkdown.Section(
                    index: 1,
                    commitOffset: 4,
                    imagePath: "frames/01.png",
                    words: [],
                    closingNote: []
                ),
                SessionMarkdown.Section(
                    index: 2,
                    commitOffset: 18,
                    imagePath: "frames/02.png",
                    words: [TimedWord(text: "second", start: 10, end: 10.4)],
                    closingNote: []
                ),
            ],
            transcript: [TimedWord(text: "second", start: 10, end: 10.4)],
            transcriptionError: nil
        )
        XCTAssertFalse(notes.contains("## 1"))
        XCTAssertTrue(notes.contains("## 2 · 0:18"))
        XCTAssertTrue(notes.contains("![1](frames/01.png)"))
        XCTAssertTrue(notes.contains("second"))
        XCTAssertFalse(notes.contains("## Transcript"))
    }

    func testTalkOnlySessionKeepsTheWords() {
        let notes = SessionMarkdown.render(
            started: "start",
            ended: "end",
            model: nil,
            sections: [],
            transcript: [
                TimedWord(text: "hello", start: 1, end: 1.2),
                TimedWord(text: "there", start: 1.3, end: 1.6),
            ],
            transcriptionError: nil
        )
        XCTAssertTrue(notes.contains("hello there"))
        XCTAssertFalse(notes.contains("## Transcript"))
        XCTAssertFalse(notes.contains("[0:01.00]"))
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
        XCTAssertEqual(text, "1. hello there\n\n2. next done")
    }

    func testPasteTextWithoutCapturesIsPlainSpeech() {
        let text = SessionMarkdown.pasteText(
            sections: [],
            transcript: [
                TimedWord(text: "hello", start: 1, end: 1.2),
                TimedWord(text: "there", start: 1.3, end: 1.6),
            ],
            transcriptionError: nil
        )
        XCTAssertEqual(text, "hello there")
    }

    func testPasteTextOmitsASilentTile() {
        let text = SessionMarkdown.pasteText(
            sections: [
                SessionMarkdown.Section(
                    index: 1,
                    commitOffset: 4,
                    imagePath: "frames/01.png",
                    words: [],
                    closingNote: []
                ),
                SessionMarkdown.Section(
                    index: 2,
                    commitOffset: 18,
                    imagePath: "frames/02.png",
                    words: [TimedWord(text: "second", start: 10, end: 10.4)],
                    closingNote: []
                ),
            ],
            transcript: [],
            transcriptionError: nil
        )
        XCTAssertEqual(text, "2. second")
    }

    func testPasteTextOmitsWordsWhenNothingWasSaid() {
        let text = SessionMarkdown.pasteText(
            sections: [
                SessionMarkdown.Section(
                    index: 1,
                    commitOffset: 4,
                    imagePath: "frames/01.png",
                    words: [],
                    closingNote: []
                ),
                SessionMarkdown.Section(
                    index: 2,
                    commitOffset: 9,
                    imagePath: "frames/02.png",
                    words: [],
                    closingNote: []
                ),
            ],
            transcript: [],
            transcriptionError: nil
        )
        XCTAssertEqual(text, "")
    }
}
