import XCTest
@testable import PromptAnnotator

final class AudioRecorderTrimTests: XCTestCase {
    func testTrimKeepsSlackBeforeCompacting() {
        var samples = Array(repeating: Float(1), count: 100)
        var dropped = 0
        AudioRecorder.trimSpeechSamplesIfNeeded(
            samples: &samples,
            dropped: &dropped,
            maxCount: 80,
            slack: 30
        )
        XCTAssertEqual(samples.count, 100)
        XCTAssertEqual(dropped, 0)
    }

    func testTrimDropsOldestWhenPastSlack() {
        var samples = Array(repeating: Float(1), count: 120)
        for i in samples.indices { samples[i] = Float(i) }
        var dropped = 0
        AudioRecorder.trimSpeechSamplesIfNeeded(
            samples: &samples,
            dropped: &dropped,
            maxCount: 80,
            slack: 20
        )
        XCTAssertEqual(samples.count, 80)
        XCTAssertEqual(dropped, 40)
        XCTAssertEqual(samples.first, 40)
        XCTAssertEqual(samples.last, 119)
    }

    func testAbsoluteCountMatchesDroppedPlusRetained() {
        var samples = Array(repeating: Float(1), count: 120)
        var dropped = 0
        AudioRecorder.trimSpeechSamplesIfNeeded(
            samples: &samples,
            dropped: &dropped,
            maxCount: 80,
            slack: 20
        )
        let absolute = dropped + samples.count
        XCTAssertEqual(absolute, 120)
        // Float round-trip of the time offset can lose a sample; integer absolute must not.
        let offset = Double(dropped) / 16_000.0
        let viaFloat = Int((offset * 16_000).rounded(.down)) + samples.count
        XCTAssertEqual(absolute, 120)
        XCTAssertLessThanOrEqual(abs(viaFloat - absolute), 1)
    }
}
