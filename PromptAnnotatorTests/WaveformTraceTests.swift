import XCTest
@testable import PromptAnnotator

final class WaveformTraceTests: XCTestCase {
    func testSilenceIsAFlatBaseline() {
        let levels = WaveformTrace.levels(samples: Array(repeating: 0, count: 2_000))
        XCTAssertEqual(levels.count, WaveformTrace.columns)
        XCTAssertTrue(levels.allSatisfy { $0 == WaveformTrace.floor })
    }

    func testRecentSpeechSitsOnTheRight() {
        let burstCount = WaveformTrace.windowSamples / 10
        let levels = WaveformTrace.levels(samples: Array(repeating: 0.85, count: burstCount))
        let head = levels.prefix(levels.count / 2)
        let tail = levels.suffix(levels.count / 10)
        XCTAssertTrue(head.allSatisfy { $0 == WaveformTrace.floor })
        XCTAssertTrue(tail.allSatisfy { $0 > 0.75 })
    }

    func testEmptyAudioStaysAtRest() {
        XCTAssertEqual(WaveformTrace.levels(samples: []), WaveformTrace.resting())
        XCTAssertEqual(WaveformTrace.fromMeter(0.02), WaveformTrace.floor)
        XCTAssertGreaterThan(WaveformTrace.fromMeter(0.6), 0.5)
    }
}
