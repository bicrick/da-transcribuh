import XCTest
@testable import PromptAnnotator

final class SettingsBehaviorTests: XCTestCase {
    func testSearchMatchesTranscriptAndIgnoresBlankQueries() {
        let match = summary(id: "a", transcript: "Thanks for watching")
        let other = summary(id: "b", transcript: "Ship the settings")
        XCTAssertEqual(HistorySearch.filter([match, other], query: "  ").map(\.id), ["a", "b"])
        XCTAssertEqual(HistorySearch.filter([match, other], query: "watch").map(\.id), ["a"])
    }

    func testQuietSpeechIsLiftedAndSilenceIsNot() {
        let quiet: [Float] = [0.1, -0.2, 0.05]
        let lifted = SampleNormalize.apply(quiet, enabled: true)
        XCTAssertEqual(Double(lifted.map { abs($0) }.max() ?? 0), 0.9, accuracy: 0.001)
        let silence: [Float] = [0.001, -0.001]
        XCTAssertEqual(SampleNormalize.apply(silence, enabled: true), silence)
        XCTAssertEqual(SampleNormalize.apply(quiet, enabled: false), quiet)
    }

    func testCapitalizeLeavesTheTileNumber() {
        XCTAssertEqual(TranscriptText.leadingCapital("1. hello there"), "1. Hello there")
        XCTAssertEqual(TranscriptText.leadingCapital("already"), "Already")
    }

    func testSilenceStopWaitsForSpeechThenQuiet() {
        var watch = SilenceWatch()
        XCTAssertFalse(watch.tick(level: 0.05, heardSpeech: false, limit: 1, delta: 0.5))
        XCTAssertFalse(watch.tick(level: 0.5, heardSpeech: true, limit: 1, delta: 0.5))
        XCTAssertFalse(watch.tick(level: 0.05, heardSpeech: true, limit: 1, delta: 0.4))
        XCTAssertTrue(watch.tick(level: 0.05, heardSpeech: true, limit: 1, delta: 0.7))
        XCTAssertFalse(SessionLimits.reachedMax(elapsed: 30, minutes: 0))
        XCTAssertTrue(SessionLimits.reachedMax(elapsed: 120, minutes: 2))
    }

    func testInputListDoesNotCrash() {
        _ = AudioInputs.devices()
    }

    func testMachineSnapshotReadsARealFootprint() {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("prompt-annotator-empty-model-\(UUID().uuidString)", isDirectory: true)
        let snapshot = MachineLoad.capture(modelReady: false, modelFolder: folder)
        XCTAssertGreaterThan(snapshot.physicalBytes, 0)
        XCTAssertEqual(snapshot.modelBytes, 0)
        XCTAssertFalse(snapshot.modelReady)
    }

    private func summary(id: String, transcript: String) -> SessionSummary {
        SessionSummary(
            id: id,
            url: URL(fileURLWithPath: "/tmp/\(id)"),
            started: nil,
            ended: nil,
            tiles: 0,
            words: transcript.split(separator: " ").count,
            model: nil,
            transcript: transcript,
            preview: transcript
        )
    }
}
