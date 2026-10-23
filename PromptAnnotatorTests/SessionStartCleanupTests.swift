import XCTest
@testable import PromptAnnotator

/// Regression: a failed start (no mic, recorder error) used to delete the previous saved session.
final class SessionStartCleanupTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("ssc-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func makeSession(_ name: String) throws -> URL {
        let url = root.appendingPathComponent(name)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        try Data("notes".utf8).write(to: url.appendingPathComponent("notes.md"))
        return url
    }

    func testFailedMicStartKeepsPreviousSession() throws {
        let previous = try makeSession("previous")
        let attempt = try makeSession("attempt")
        SessionStartCleanup.removeAttemptFolder(attempt)
        XCTAssertTrue(FileManager.default.fileExists(atPath: previous.appendingPathComponent("notes.md").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: attempt.path))
    }

    func testFailureBeforeFolderCreatedRemovesNothing() throws {
        let previous = try makeSession("previous")
        SessionStartCleanup.removeAttemptFolder(nil)
        XCTAssertTrue(FileManager.default.fileExists(atPath: previous.path))
    }
}
