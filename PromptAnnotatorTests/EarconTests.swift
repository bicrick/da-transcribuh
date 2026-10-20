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

    func testBlipsStayLowAndShort() {
        let start = Earcon.samples(.start)
        let spoken = Earcon.samples(.stopSpoken)
        let silent = Earcon.samples(.stopSilent)
        let tile = Earcon.samples(.tile)

        XCTAssertLessThan(dominantFrequency(start), 280)
        XCTAssertGreaterThan(dominantFrequency(start), 70)
        XCTAssertLessThan(dominantFrequency(spoken), 280)
        XCTAssertLessThan(dominantFrequency(silent), 160)
        XCTAssertLessThan(dominantFrequency(tile), 280)
        XCTAssertLessThan(seconds(tile), 0.08)
        XCTAssertLessThan(seconds(start), 0.35)
        XCTAssertLessThan(seconds(silent), seconds(spoken))
        for samples in [start, spoken, silent, tile] {
            XCTAssertLessThan(samples.map { abs($0) }.max() ?? 0, 0.9)
        }
    }

    private func seconds(_ samples: [Float]) -> Double {
        Double(samples.count) / 44_100
    }

    private func dominantFrequency(_ samples: [Float]) -> Double {
        guard let peakIndex = samples.indices.max(by: { abs(samples[$0]) < abs(samples[$1]) }) else {
            return 0
        }
        let radius = 1400
        let start = max(0, peakIndex - radius)
        let end = min(samples.count, peakIndex + radius)
        let window = Array(samples[start..<end])
        let minLag = Int(44_100 / 400)
        let maxLag = min(Int(44_100 / 50), window.count - 1)
        var bestLag = minLag
        var best = -Float.greatestFiniteMagnitude
        guard maxLag > minLag else { return 0 }
        for lag in minLag...maxLag {
            var corr: Float = 0
            let limit = window.count - lag
            var index = 0
            while index < limit {
                corr += window[index] * window[index + lag]
                index += 1
            }
            if corr > best {
                best = corr
                bestLag = lag
            }
        }
        return 44_100 / Double(bestLag)
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

final class FrequencyBandTests: XCTestCase {
    func testLowAndHighTonesLightDifferentBars() {
        let count = 19
        let low = FrequencyBands.levels(samples: tone(band: 2, count: count), count: count)
        let high = FrequencyBands.levels(samples: tone(band: 16, count: count), count: count)
        XCTAssertEqual(low.count, count)
        XCTAssertGreaterThan(low[2], low[16])
        XCTAssertGreaterThan(high[16], high[2])
    }

    func testSilenceStaysAtRest() {
        let quiet = FrequencyBands.levels(samples: Array(repeating: 0, count: 512), count: 8)
        XCTAssertTrue(quiet.allSatisfy { $0 < 0.2 })
    }

    func testSmoothingKeepsEachPitchInItsSlot() {
        let rest = FrequencyBands.resting(8)
        let eased = FrequencyBands.smooth(rest, toward: [1, 0.1, 0.1, 0.1, 0.1, 0.1, 0.1, 0.1])
        XCTAssertEqual(eased.count, 8)
        XCTAssertGreaterThan(eased[0], eased[7])
        XCTAssertLessThan(eased[0], 1)
    }

    func testAQuietToneStillRises() {
        let count = 19
        let levels = FrequencyBands.levels(samples: tone(band: 8, count: count, amplitude: 0.01), count: count)
        XCTAssertGreaterThan(levels[8], 0.4)
        XCTAssertGreaterThan(levels[8], levels[2])
        XCTAssertGreaterThan(levels[8], levels[16])
    }

    func testSmoothingFollowsTheFrameClock() {
        let target: [CGFloat] = [1, 0.2, 0.2, 1]
        var levels = FrequencyBands.resting(4)
        levels = FrequencyBands.smooth(levels, toward: target, delta: 1.0 / 60.0)
        XCTAssertGreaterThan(levels[0], 0.2)
        XCTAssertLessThan(levels[0], 0.7)
        for _ in 0..<8 {
            levels = FrequencyBands.smooth(levels, toward: target, delta: 1.0 / 60.0)
        }
        XCTAssertGreaterThan(levels[0], 0.85)
        XCTAssertGreaterThan(levels[0], levels[1])
    }

    private func tone(band: Int, count: Int, amplitude: Float = 0.6) -> [Float] {
        let hz = FrequencyBands.frequency(band: band, count: count)
        return (0..<FrequencyBands.window).map { index in
            let angle = 2 * Float.pi * Float(hz) * Float(index) / Float(FrequencyBands.sampleRate)
            return sin(angle) * amplitude
        }
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
