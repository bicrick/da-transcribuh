import XCTest
@testable import PromptAnnotator

final class SessionLibraryTests: XCTestCase {
    func testSummariesAndStatsReadSessionJSON() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("prompt-annotator-library-\(UUID().uuidString)", isDirectory: true)
        let folder = root.appendingPathComponent("2026-10-19T12-00-00", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let json = """
        {
          "coordinateSpace": "display points, origin top-left, y down",
          "endedAt": "2026-10-19T12:02:30Z",
          "groups": [
            {
              "closingNote": [],
              "committedAt": 10,
              "display": {
                "frameHeight": 900,
                "frameWidth": 1440,
                "frameX": 0,
                "frameY": 0,
                "heightPixels": 1800,
                "heightPoints": 900,
                "id": 1,
                "widthPixels": 2880,
                "widthPoints": 1440
              },
              "frame": "frames/01.png",
              "index": 1,
              "shapes": [],
              "words": []
            }
          ],
          "model": "small.en_217MB",
          "startedAt": "2026-10-19T12:00:00Z",
          "version": 1,
          "words": [
            {"end": 0.4, "start": 0.1, "text": " hello "},
            {"end": 0.8, "start": 0.5, "text": "   "}
          ]
        }
        """
        try json.write(to: folder.appendingPathComponent("session.json"), atomically: true, encoding: .utf8)

        let sessions = SessionLibrary.summaries(in: root)
        XCTAssertEqual(sessions.count, 1)
        XCTAssertEqual(sessions[0].tiles, 1)
        XCTAssertEqual(sessions[0].words, 1)
        XCTAssertEqual(sessions[0].transcript, "hello")
        XCTAssertEqual(sessions[0].preview, "hello")
        XCTAssertEqual(sessions[0].model, "small.en_217MB")
        XCTAssertEqual(sessions[0].duration, 150, accuracy: 0.001)

        let stats = SessionLibrary.stats(from: sessions)
        XCTAssertEqual(stats.sessions, 1)
        XCTAssertEqual(stats.tiles, 1)
        XCTAssertEqual(stats.words, 1)
        XCTAssertEqual(stats.minutes, 3)
    }

    func testCachedSummariesFollowRewritesAndRemovals() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("prompt-annotator-library-cache-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        func write(_ name: String, words: [String]) throws {
            let folder = root.appendingPathComponent(name, isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let list = words.enumerated().map { i, w in
                "{\"end\": \(Double(i) + 0.4), \"start\": \(Double(i)), \"text\": \" \(w)\"}"
            }.joined(separator: ",")
            let json = """
            {"coordinateSpace": "x", "endedAt": "2026-10-19T12:02:30Z", "groups": [],
             "model": "m", "startedAt": "2026-10-19T12:00:00Z", "version": 1, "words": [\(list)]}
            """
            try json.write(to: folder.appendingPathComponent("session.json"), atomically: true, encoding: .utf8)
        }

        try write("2026-10-19T12-00-00", words: ["hello"])
        try write("2026-10-19T13-00-00", words: ["one", "two"])
        XCTAssertEqual(SessionLibrary.summaries(in: root).map(\.words).sorted(), [1, 2])

        // Second read is served from cache and still identical.
        XCTAssertEqual(SessionLibrary.summaries(in: root).map(\.words).sorted(), [1, 2])

        try write("2026-10-19T12-00-00", words: ["hello", "again", "world"])
        XCTAssertEqual(SessionLibrary.summaries(in: root).map(\.words).sorted(), [2, 3])

        try FileManager.default.removeItem(at: root.appendingPathComponent("2026-10-19T13-00-00"))
        XCTAssertEqual(SessionLibrary.summaries(in: root).map(\.words), [3])
    }
}
