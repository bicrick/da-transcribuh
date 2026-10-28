import XCTest
@testable import PromptAnnotator

/// Small pure-logic checks for helpers that had little or no direct coverage.
final class TimeFormatTests: XCTestCase {
    func testClockRoundsDownAndAddsHoursOnlyWhenNeeded() {
        XCTAssertEqual(TimeFormat.clock(0), "0:00")
        XCTAssertEqual(TimeFormat.clock(59.9), "0:59")
        XCTAssertEqual(TimeFormat.clock(61), "1:01")
        XCTAssertEqual(TimeFormat.clock(3661), "1:01:01")
    }

    func testClockClampsNegativeToZero() {
        XCTAssertEqual(TimeFormat.clock(-5), "0:00")
    }

    func testPreciseKeepsHundredths() {
        XCTAssertEqual(TimeFormat.precise(0), "0:00.00")
        XCTAssertEqual(TimeFormat.precise(61.25), "1:01.25")
        XCTAssertEqual(TimeFormat.precise(3661.5), "1:01:01.50")
        XCTAssertEqual(TimeFormat.precise(-1), "0:00.00")
    }

    func testStampFormattersRoundTrip() throws {
        let folder = try XCTUnwrap(Stamp.folder.date(from: "2026-10-28T05-01-02"))
        XCTAssertEqual(Stamp.folder.string(from: folder), "2026-10-28T05-01-02")
        let iso = try XCTUnwrap(Stamp.iso.date(from: "2026-10-28T10:01:02Z"))
        XCTAssertEqual(Stamp.iso.string(from: iso), "2026-10-28T10:01:02Z")
    }
}

final class SpeechGateDecayTests: XCTestCase {
    func testSingleLoudBufferDecaysAway() {
        var voiced = 0
        var heard = false
        SpeechGate.note(level: 0.5, voicedBuffers: &voiced, heard: &heard)
        XCTAssertEqual(voiced, 1)
        XCTAssertFalse(heard)
        SpeechGate.note(level: 0.1, voicedBuffers: &voiced, heard: &heard)
        XCTAssertEqual(voiced, 0)
        XCTAssertFalse(heard)
        SpeechGate.note(level: 0.1, voicedBuffers: &voiced, heard: &heard)
        XCTAssertEqual(voiced, 0)
    }

    func testTwoLoudBuffersMarkSpeechAndLatch() {
        var voiced = 0
        var heard = false
        SpeechGate.note(level: SpeechGate.threshold, voicedBuffers: &voiced, heard: &heard)
        SpeechGate.note(level: 0.9, voicedBuffers: &voiced, heard: &heard)
        XCTAssertTrue(heard)
        XCTAssertEqual(voiced, SpeechGate.voicedNeeded)
        SpeechGate.note(level: 0, voicedBuffers: &voiced, heard: &heard)
        XCTAssertTrue(heard)
        XCTAssertEqual(voiced, SpeechGate.voicedNeeded)
    }
}

final class SilenceWatchEdgeTests: XCTestCase {
    func testZeroLimitNeverStopsAndResets() {
        var watch = SilenceWatch(accumulated: 5)
        XCTAssertFalse(watch.tick(level: 0, heardSpeech: true, limit: 0, delta: 10))
        XCTAssertEqual(watch.accumulated, 0)
    }

    func testLoudBufferResetsTheQuietClock() {
        var watch = SilenceWatch()
        XCTAssertFalse(watch.tick(level: 0, heardSpeech: true, limit: 1, delta: 0.75))
        XCTAssertFalse(watch.tick(level: 0.9, heardSpeech: true, limit: 1, delta: 0.5))
        XCTAssertEqual(watch.accumulated, 0)
        XCTAssertFalse(watch.tick(level: 0, heardSpeech: true, limit: 1, delta: 0.5))
        XCTAssertTrue(watch.tick(level: 0, heardSpeech: true, limit: 1, delta: 0.5))
    }

    func testMaxSessionBoundaries() {
        XCTAssertTrue(SessionLimits.reachedMax(elapsed: 120, minutes: 2))
        XCTAssertFalse(SessionLimits.reachedMax(elapsed: 119.9, minutes: 2))
        XCTAssertFalse(SessionLimits.reachedMax(elapsed: 999, minutes: -1))
    }
}

final class SmallTextAndSampleTests: XCTestCase {
    func testLeadingCapitalEdgeCases() {
        XCTAssertEqual(TranscriptText.leadingCapital(""), "")
        XCTAssertEqual(TranscriptText.leadingCapital("123"), "123")
        XCTAssertEqual(TranscriptText.leadingCapital("  hi there"), "  Hi there")
    }

    func testNormalizeLeavesEmptyLoudAndFloorSamplesAlone() {
        XCTAssertEqual(SampleNormalize.apply([], enabled: true), [])
        let loud: [Float] = [0.8, -0.3]
        XCTAssertEqual(SampleNormalize.apply(loud, enabled: true), loud)
        let floor: [Float] = [0.02, -0.01]
        XCTAssertEqual(SampleNormalize.apply(floor, enabled: true), floor)
    }

    func testStoredFallbacksForUnknownRawValues() {
        XCTAssertEqual(IslandStyle.stored("bogus"), .classic)
        XCTAssertEqual(AppAppearance.stored(nil), .system)
        XCTAssertEqual(AppAppearance.stored("bogus"), .system)
        XCTAssertEqual(AppAppearance.stored("dark"), .dark)
    }
}

@MainActor
final class AppSettingsLoadTests: XCTestCase {
    private func freshDefaults() -> (UserDefaults, String) {
        let name = "PromptAnnotatorTests.load-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return (defaults, name)
    }

    func testFreshInstallDefaults() {
        let (defaults, name) = freshDefaults()
        defer { defaults.removePersistentDomain(forName: name) }
        let settings = AppSettings(defaults: defaults)
        XCTAssertTrue(settings.soundEnabled)
        XCTAssertEqual(settings.soundVolume, 0.7, accuracy: 0.0001)
        XCTAssertEqual(settings.soundTheme, .classic)
        XCTAssertEqual(settings.defaultTool, .pen)
        XCTAssertEqual(settings.islandStyle, .classic)
        XCTAssertTrue(settings.showInDock)
        XCTAssertEqual(settings.silenceStopSeconds, 0)
        XCTAssertEqual(settings.maxSessionMinutes, 0)
    }

    func testGarbageStoredValuesFallBack() {
        let (defaults, name) = freshDefaults()
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set("bogus", forKey: "sound.theme")
        defaults.set("bogus", forKey: "tool.default")
        defaults.set("mini", forKey: "island.style")
        defaults.set("bogus", forKey: "app.appearance")
        let settings = AppSettings(defaults: defaults)
        XCTAssertEqual(settings.soundTheme, .classic)
        XCTAssertEqual(settings.defaultTool, .pen)
        XCTAssertEqual(settings.islandStyle, .compact)
        XCTAssertEqual(settings.appearance, .system)
    }

    func testStoredVolumeIsClamped() {
        let (defaults, name) = freshDefaults()
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set(3.0, forKey: "sound.volume")
        XCTAssertEqual(AppSettings(defaults: defaults).soundVolume, 1, accuracy: 0.0001)
        defaults.set(-1.0, forKey: "sound.volume")
        XCTAssertEqual(AppSettings(defaults: defaults).soundVolume, 0, accuracy: 0.0001)
    }
}
