import XCTest
@testable import PromptAnnotator

final class SessionEmptyTakeTests: XCTestCase {
    func testDiscardEmptyWhitespaceAndNoSpeechAnnotations() {
        XCTAssertTrue(SessionEmptyTake.shouldDiscard(words: [], tileCount: 0))
        XCTAssertTrue(SessionEmptyTake.shouldDiscard(
            words: [TimedWord(text: "   ", start: 0, end: 0.1)],
            tileCount: 0
        ))
        XCTAssertTrue(SessionEmptyTake.shouldDiscard(
            words: [TimedWord(text: "[BLANK_AUDIO]", start: 0, end: 1)],
            tileCount: 0
        ))
        XCTAssertTrue(SessionEmptyTake.shouldDiscard(
            words: [TimedWord(text: "(silence)", start: 0, end: 1)],
            tileCount: 0
        ))
        XCTAssertTrue(SessionEmptyTake.shouldDiscard(
            words: [TimedWord(text: "[No speech]", start: 0, end: 1)],
            tileCount: 0
        ))
        XCTAssertEqual(SessionEmptyTake.spokenContent([
            TimedWord(text: "NO_SPEECH", start: 0, end: 1),
        ]), "")
    }

    func testKeepSpeechOnlyTakes() {
        XCTAssertFalse(SessionEmptyTake.shouldDiscard(
            words: [
                TimedWord(text: "hello", start: 0, end: 0.2),
                TimedWord(text: "there", start: 0.3, end: 0.5),
            ],
            tileCount: 0
        ))
    }

    func testKeepSilentTakesWithScreenshots() {
        XCTAssertFalse(SessionEmptyTake.shouldDiscard(words: [], tileCount: 1))
        XCTAssertFalse(SessionEmptyTake.shouldDiscard(
            words: [TimedWord(text: "[BLANK_AUDIO]", start: 0, end: 1)],
            tileCount: 2
        ))
    }

    func testKeepTranscriptionFailuresEvenWhenEmpty() {
        XCTAssertFalse(SessionEmptyTake.shouldDiscard(
            words: [],
            tileCount: 0,
            transcriptionError: "model unavailable"
        ))
    }

    func testPurgeRemovesEmptyFoldersKeepsSpeechAndTiles() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("empty-take-purge-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let empty = root.appendingPathComponent("empty", isDirectory: true)
        try writeSessionJSON(
            at: empty,
            wordsJSON: #"[{"end":0.2,"start":0,"text":"  "}]"#,
            groupsJSON: "[]"
        )

        let blankAudio = root.appendingPathComponent("blank", isDirectory: true)
        try writeSessionJSON(
            at: blankAudio,
            wordsJSON: #"[{"end":1,"start":0,"text":"[BLANK_AUDIO]"}]"#,
            groupsJSON: "[]"
        )

        let speech = root.appendingPathComponent("speech", isDirectory: true)
        try writeSessionJSON(
            at: speech,
            wordsJSON: #"[{"end":0.2,"start":0,"text":"hi"}]"#,
            groupsJSON: "[]"
        )

        let tiles = root.appendingPathComponent("tiles", isDirectory: true)
        try writeSessionJSON(
            at: tiles,
            wordsJSON: "[]",
            groupsJSON: """
            [{
              "closingNote": [],
              "committedAt": 1,
              "display": {
                "frameHeight": 100, "frameWidth": 100, "frameX": 0, "frameY": 0,
                "heightPixels": 100, "heightPoints": 100, "id": 1,
                "widthPixels": 100, "widthPoints": 100
              },
              "frame": "frames/01.png",
              "index": 1,
              "shapes": [],
              "words": []
            }]
            """
        )

        let orphan = root.appendingPathComponent("orphan", isDirectory: true)
        try FileManager.default.createDirectory(at: orphan, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(
            at: orphan.appendingPathComponent("frames", isDirectory: true),
            withIntermediateDirectories: true
        )

        let failed = root.appendingPathComponent("failed", isDirectory: true)
        try writeSessionJSON(
            at: failed,
            wordsJSON: "[]",
            groupsJSON: "[]",
            transcriptionError: "model unavailable"
        )

        let removed = SessionEmptyTake.purgeEmptySessions(in: root)
        XCTAssertEqual(removed, 3) // empty, blank, orphan

        let remaining = Set(
            (try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil))
                .map(\.lastPathComponent)
        )
        XCTAssertEqual(remaining, ["speech", "tiles", "failed"])
    }

    func testOneTimeCleanupFlagSkipsSecondPass() throws {
        let name = "PromptAnnotatorTests.emptyTakeCleanup"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        defer { defaults.removePersistentDomain(forName: name) }

        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("empty-take-once-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let empty = root.appendingPathComponent("empty", isDirectory: true)
        try writeSessionJSON(at: empty, wordsJSON: "[]", groupsJSON: "[]")

        // Direct purge API (launch helper needs real SessionPaths root).
        XCTAssertEqual(SessionEmptyTake.purgeEmptySessions(in: root), 1)
        XCTAssertEqual(SessionEmptyTake.purgeEmptySessions(in: root), 0)

        defaults.set(false, forKey: "sessions.purgedEmpty.v1")
        // Mark flag as done without walking (no sessions root override).
        defaults.set(true, forKey: "sessions.purgedEmpty.v1")
        XCTAssertEqual(SessionEmptyTake.runOneTimeCleanupIfNeeded(defaults: defaults), 0)
        XCTAssertTrue(defaults.bool(forKey: "sessions.purgedEmpty.v1"))
    }

    private func writeSessionJSON(
        at folder: URL,
        wordsJSON: String,
        groupsJSON: String,
        transcriptionError: String? = nil
    ) throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let errLine: String
        if let transcriptionError {
            errLine = ",\n          \"transcriptionError\": \"\(transcriptionError)\""
        } else {
            errLine = ""
        }
        let json = """
        {
          "coordinateSpace": "display points, origin top-left, y down",
          "endedAt": "2026-10-19T12:02:30Z",
          "groups": \(groupsJSON),
          "model": null,
          "startedAt": "2026-10-19T12:00:00Z",
          "version": 1,
          "words": \(wordsJSON)\(errLine)
        }
        """
        try json.write(to: folder.appendingPathComponent("session.json"), atomically: true, encoding: .utf8)
    }
}
