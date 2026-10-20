import XCTest
@testable import PromptAnnotator

final class EarconTests: XCTestCase {
    func testTonesAreDistinctWaves() {
        let start = Earcon.wave(.start)
        let spoken = Earcon.wave(.stopSpoken)
        let silent = Earcon.wave(.stopSilent)
        XCTAssertEqual(start.prefix(4), Data("RIFF".utf8))
        XCTAssertNotEqual(start, spoken)
        XCTAssertNotEqual(spoken, silent)
        XCTAssertGreaterThan(silent.count, 44)
    }
}

final class SpeechGateTests: XCTestCase {
    func testAClickDoesNotCountAsSpeech() {
        var voiced = 0
        var heard = false
        SpeechGate.note(level: 0.8, voicedBuffers: &voiced, heard: &heard)
        SpeechGate.note(level: 0.05, voicedBuffers: &voiced, heard: &heard)
        XCTAssertFalse(heard)
    }

    func testSustainedSoundCountsAsSpeech() {
        var voiced = 0
        var heard = false
        SpeechGate.note(level: 0.4, voicedBuffers: &voiced, heard: &heard)
        SpeechGate.note(level: 0.45, voicedBuffers: &voiced, heard: &heard)
        XCTAssertTrue(heard)
    }
}

final class WaveformMotionTests: XCTestCase {
    func testLoadingFramesMove() {
        let first = WaveformMotion.loading(frame: 0, count: 8)
        let later = WaveformMotion.loading(frame: 6, count: 8)
        XCTAssertEqual(first.count, 8)
        XCTAssertNotEqual(first, later)
        XCTAssertTrue(first.allSatisfy { $0 >= 0.08 && $0 <= 1 })
    }
}
