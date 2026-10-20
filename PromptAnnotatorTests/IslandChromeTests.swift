import XCTest
@testable import PromptAnnotator

final class IslandChromeTests: XCTestCase {
    func testRecordingChromeMatchesTheStyle() {
        let classic = IslandSlots.recording(style: .classic, captures: 0)
        XCTAssertEqual(classic.label, 1)
        XCTAssertEqual(classic.clock, 1)
        XCTAssertEqual(classic.dot, 0)
        XCTAssertEqual(classic.chip, 0)

        let counted = IslandSlots.recording(style: .classic, captures: 2)
        XCTAssertEqual(counted.chip, 1)

        let compact = IslandSlots.recording(style: .compact, captures: 1)
        XCTAssertEqual(compact.dot, 1)
        XCTAssertEqual(compact.label, 0)
        XCTAssertEqual(compact.clock, 1)
        XCTAssertEqual(compact.chip, 1)

        XCTAssertEqual(IslandSlots.recording(style: .minimal, captures: 4), .closed)
        XCTAssertEqual(IslandSlots.recording(style: .hidden, captures: 4), .closed)
    }

    func testProcessingLetsTheRecordingChromeLeave() {
        let transcribing = IslandSlots.processing(phase: .transcribing)
        XCTAssertEqual(transcribing, .closed)

        let early = IslandSlots.processing(phase: .downloading(0))
        XCTAssertEqual(early.percent, 0)
        XCTAssertEqual(early.label, 0)
        XCTAssertEqual(early.chip, 0)

        let downloading = IslandSlots.processing(phase: .downloading(0.42))
        XCTAssertEqual(downloading.percent, 1)
        XCTAssertEqual(downloading.label, 0)
        XCTAssertEqual(downloading.clock, 0)
        XCTAssertEqual(downloading.chip, 0)
    }

    func testTheCombStaysCenteredAndDoesNotChangeFrame() {
        for style in IslandStyle.allCases {
            let recording = IslandMetrics.layout(
                style: style,
                slots: IslandSlots.recording(style: style, captures: 2),
                captures: 2,
                elapsed: 12
            )
            let processing = IslandMetrics.layout(
                style: style,
                slots: IslandSlots.processing(phase: .transcribing),
                captures: 2,
                elapsed: 12
            )
            XCTAssertEqual(recording.wave, processing.wave, "\(style)")
            XCTAssertEqual(recording.panel.height, processing.panel.height, "\(style)")
            let left = IslandMetrics.inset + recording.side
            let waveEnd = left + recording.wave.width
            let right = recording.panel.width - IslandMetrics.inset - recording.side
            XCTAssertEqual(waveEnd, right, accuracy: 0.01, "\(style)")
            XCTAssertEqual(recording.panel.width / 2, left + recording.wave.width / 2, accuracy: 0.01, "\(style)")
            if style == .minimal || style == .hidden {
                XCTAssertEqual(recording.panel, processing.panel, "\(style)")
            } else {
                XCTAssertGreaterThan(recording.panel.width, processing.panel.width, "\(style)")
                XCTAssertEqual(processing.side, 0, "\(style)")
                XCTAssertGreaterThan(recording.side, 0, "\(style)")
            }
        }
    }

    func testClosingSlotsCollapseWithoutCrossingTheTarget() {
        let step = IslandSlots.step(1, 0, delta: 1.0 / 60.0, tau: 0.13)
        XCTAssertGreaterThan(step, 0.8)
        XCTAssertLessThan(step, 1)
        var amount: CGFloat = 1
        for _ in 0..<90 {
            amount = IslandSlots.step(amount, 0, delta: 1.0 / 60.0, tau: 0.13)
            XCTAssertGreaterThanOrEqual(amount, 0)
        }
        XCTAssertLessThan(amount, 0.01)
        XCTAssertEqual(IslandSlots.opacity(for: 1), 1)
        XCTAssertEqual(IslandSlots.opacity(for: 0), 0)
        XCTAssertLessThan(IslandSlots.opacity(for: 0.2), 0.5)
    }

    func testAShortSilenceDoesNotDropTheComb() {
        let loud: [CGFloat] = [0.8, 0.3, 0.3]
        var quiet: TimeInterval = 0
        let held = FrequencyBands.follow(
            loud,
            raw: FrequencyBands.resting(3),
            silent: true,
            quietFor: &quiet,
            delta: 0.02
        )
        XCTAssertEqual(held, loud)
        XCTAssertLessThan(quiet, 0.12)

        quiet = 0.12
        let falling = FrequencyBands.follow(
            loud,
            raw: FrequencyBands.resting(3),
            silent: true,
            quietFor: &quiet,
            delta: 0.02
        )
        XCTAssertLessThan(falling[0], loud[0])
        XCTAssertGreaterThan(falling[0], 0.4)
    }
}
