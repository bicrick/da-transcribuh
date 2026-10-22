import XCTest
@testable import PromptAnnotator

final class NonSpeechFilterTests: XCTestCase {
    func testDropsBracketedAndParenthesizedSoundLabels() {
        XCTAssertTrue(NonSpeechFilter.isAnnotationToken("[BLANK_AUDIO]"))
        XCTAssertTrue(NonSpeechFilter.isAnnotationToken("(silence)"))
        XCTAssertTrue(NonSpeechFilter.isAnnotationToken("[Music]"))
        XCTAssertTrue(NonSpeechFilter.isAnnotationToken("(typing)"))
        XCTAssertTrue(NonSpeechFilter.isAnnotationToken("[keyboard clacking]"))
        XCTAssertTrue(NonSpeechFilter.isAnnotationToken("BLANK_AUDIO"))
        XCTAssertTrue(NonSpeechFilter.isAnnotationToken("♪"))
    }

    func testKeepsRealSpokenParentheticals() {
        XCTAssertFalse(NonSpeechFilter.isAnnotationToken("(yesterday)"))
        XCTAssertFalse(NonSpeechFilter.isAnnotationToken("(I think)"))
        XCTAssertFalse(NonSpeechFilter.isAnnotationToken("[important]"))
        XCTAssertFalse(NonSpeechFilter.isAnnotationToken("hello"))
        // Spoken words that happen to match label names must stay.
        XCTAssertFalse(NonSpeechFilter.isAnnotationToken("silence"))
        XCTAssertFalse(NonSpeechFilter.isAnnotationToken("music"))
        XCTAssertFalse(NonSpeechFilter.isAnnotationToken("typing"))
    }

    func testScrubRemovesAnnotationsAndCollapsesSpace() {
        XCTAssertEqual(
            NonSpeechFilter.scrub("hello [BLANK_AUDIO] there"),
            "hello there"
        )
        XCTAssertEqual(
            NonSpeechFilter.scrub("(silence)"),
            ""
        )
        XCTAssertEqual(
            NonSpeechFilter.scrub("Start (typing) and [Music] end"),
            "Start and end"
        )
        XCTAssertEqual(
            NonSpeechFilter.scrub("I said (yesterday) yes"),
            "I said (yesterday) yes"
        )
        XCTAssertEqual(
            NonSpeechFilter.scrub("  [Music]  "),
            ""
        )
    }

    func testFilterWordsDropsWholeAndSplitAnnotations() {
        let words = [
            TimedWord(text: " hello", start: 0, end: 0.2),
            TimedWord(text: "[BLANK_AUDIO]", start: 0.3, end: 0.5),
            TimedWord(text: " there", start: 0.6, end: 0.8),
            TimedWord(text: "(", start: 1.0, end: 1.0),
            TimedWord(text: "silence", start: 1.0, end: 1.2),
            TimedWord(text: ")", start: 1.2, end: 1.2),
            TimedWord(text: " world", start: 1.3, end: 1.5),
        ]
        let filtered = NonSpeechFilter.filterWords(words)
        XCTAssertEqual(
            filtered.map { $0.text.trimmingCharacters(in: .whitespaces) },
            ["hello", "there", "world"]
        )
    }

    func testFilterWordsKeepsSpokenParentheticalSpans() {
        let words = [
            TimedWord(text: "I", start: 0, end: 0.1),
            TimedWord(text: "said", start: 0.1, end: 0.3),
            TimedWord(text: "(", start: 0.3, end: 0.3),
            TimedWord(text: "quietly", start: 0.3, end: 0.5),
            TimedWord(text: ")", start: 0.5, end: 0.5),
            TimedWord(text: "yes", start: 0.5, end: 0.7),
        ]
        let filtered = NonSpeechFilter.filterWords(words)
        XCTAssertEqual(filtered.map(\.text), words.map(\.text))
    }

    func testSpokenTextPathNeverSurfacesBlankAudio() {
        let words = [
            TimedWord(text: "[BLANK_AUDIO]", start: 0, end: 1),
            TimedWord(text: "(silence)", start: 1, end: 2),
        ]
        XCTAssertEqual(Aligner.spokenText(words), "")
    }

    func testSpokenWordSilenceIsKept() {
        let words = [
            TimedWord(text: "there", start: 0, end: 0.2),
            TimedWord(text: "was", start: 0.2, end: 0.3),
            TimedWord(text: "silence", start: 0.3, end: 0.6),
            TimedWord(text: "then", start: 0.6, end: 0.8),
        ]
        XCTAssertEqual(Aligner.spokenText(words), "there was silence then")
    }

    func testSilenceOnlySessionPasteStaysEmpty() {
        let paste = SessionMarkdown.pasteText(
            sections: [],
            transcript: [
                TimedWord(text: "[Music]", start: 0, end: 1),
                TimedWord(text: "(typing)", start: 1, end: 2),
            ],
            transcriptionError: nil
        )
        XCTAssertEqual(paste, "")
    }
}
