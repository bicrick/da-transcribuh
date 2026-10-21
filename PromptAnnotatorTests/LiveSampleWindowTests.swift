import XCTest
@testable import PromptAnnotator

final class LiveSampleWindowTests: XCTestCase {
    private let rate = 16_000

    func testNoClipReturnsTheBufferWhenShort() {
        let samples = Array(repeating: Float(0.1), count: rate * 10)
        let slice = LiveSampleWindow.slice(
            samples: samples,
            bufferStart: 0,
            clipStart: 0,
            sampleRate: rate
        )
        XCTAssertEqual(slice.timeOffset, 0)
        XCTAssertEqual(slice.samples.count, samples.count)
    }

    func testLongBufferWithoutClipKeepsOnlyTheTail() {
        let seconds = 90
        let samples = Array(repeating: Float(0.1), count: rate * seconds)
        let slice = LiveSampleWindow.slice(
            samples: samples,
            bufferStart: 0,
            clipStart: 0,
            sampleRate: rate
        )
        XCTAssertEqual(slice.samples.count, Int(LiveSampleWindow.maxSeconds * Double(rate)))
        XCTAssertEqual(slice.timeOffset, Double(seconds) - LiveSampleWindow.maxSeconds, accuracy: 0.001)
    }

    func testClipStartSlicesWithOverlap() {
        let samples = Array(repeating: Float(0.1), count: rate * 40)
        let clip: TimeInterval = 30
        let slice = LiveSampleWindow.slice(
            samples: samples,
            bufferStart: 0,
            clipStart: clip,
            sampleRate: rate
        )
        XCTAssertEqual(slice.timeOffset, clip - LiveSampleWindow.overlap, accuracy: 0.001)
        let expected = Int((Double(40) - (clip - LiveSampleWindow.overlap)) * Double(rate))
        XCTAssertEqual(slice.samples.count, expected)
    }

    func testBufferStartShiftsAbsoluteTime() {
        let samples = Array(repeating: Float(0.2), count: rate * 20)
        let slice = LiveSampleWindow.slice(
            samples: samples,
            bufferStart: 60,
            clipStart: 70,
            sampleRate: rate
        )
        XCTAssertEqual(slice.timeOffset, 70 - LiveSampleWindow.overlap, accuracy: 0.001)
        XCTAssertLessThan(slice.samples.count, samples.count)
    }

    func testEmptyBuffer() {
        let slice = LiveSampleWindow.slice(
            samples: [],
            bufferStart: 12,
            clipStart: 12,
            sampleRate: rate
        )
        XCTAssertTrue(slice.samples.isEmpty)
        XCTAssertEqual(slice.timeOffset, 12)
    }

    /// Final/tail decode must keep everything after clipStart, not a live-sized tail.
    func testUncappedSliceKeepsFullRemainderAfterClip() {
        let seconds = 180
        let samples = Array(repeating: Float(0.1), count: rate * seconds)
        let clip: TimeInterval = 30
        let slice = LiveSampleWindow.slice(
            samples: samples,
            bufferStart: 0,
            clipStart: clip,
            sampleRate: rate,
            maxSeconds: nil
        )
        XCTAssertEqual(slice.timeOffset, clip - LiveSampleWindow.overlap, accuracy: 0.001)
        let expected = Int((Double(seconds) - (clip - LiveSampleWindow.overlap)) * Double(rate))
        XCTAssertEqual(slice.samples.count, expected)
        XCTAssertGreaterThan(slice.samples.count, Int(LiveSampleWindow.maxSeconds * Double(rate)))
    }
}
