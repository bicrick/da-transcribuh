import XCTest
@testable import PromptAnnotator

final class HotkeyActivationMachineTests: XCTestCase {

    // MARK: - Tap toggle + hold PTT

    func testTapStartsHandsFree() {
        var m = HotkeyActivationMachine()
        XCTAssertEqual(
            m.handle(.down(at: 1.0), behavior: .holdAndDoubleTap),
            [.armHoldTimer(deadline: 1.0 + HotkeyActivationMachine.holdThreshold)]
        )
        // Quick release before threshold → hands-free on
        XCTAssertEqual(
            m.handle(.up(at: 1.1), behavior: .holdAndDoubleTap),
            [.cancelHoldTimer, .startRecording]
        )
        XCTAssertEqual(m.phase, .handsFree)
    }

    func testHoldStartsPushToTalkAndReleaseStops() {
        var m = HotkeyActivationMachine()
        _ = m.handle(.down(at: 1.0), behavior: .holdAndDoubleTap)
        XCTAssertEqual(
            m.handle(.holdThresholdReached, behavior: .holdAndDoubleTap),
            [.startRecording]
        )
        XCTAssertEqual(m.phase, .holding(downAt: 1.0))
        XCTAssertEqual(
            m.handle(.up(at: 1.8), behavior: .holdAndDoubleTap),
            [.stopRecording]
        )
        XCTAssertEqual(m.phase, .idle)
    }

    func testTapWhileHandsFreeStops() {
        var m = HotkeyActivationMachine()
        _ = m.handle(.down(at: 1.0), behavior: .holdAndDoubleTap)
        _ = m.handle(.up(at: 1.1), behavior: .holdAndDoubleTap)
        // Second tap down → stopping
        XCTAssertEqual(m.handle(.down(at: 2.0), behavior: .holdAndDoubleTap), [])
        XCTAssertEqual(m.phase, .handsFreeStopping(downAt: 2.0))
        XCTAssertEqual(
            m.handle(.up(at: 2.1), behavior: .holdAndDoubleTap),
            [.stopRecording]
        )
        XCTAssertEqual(m.phase, .idle)
    }

    func testHoldWhileHandsFreeAlsoStopsOnRelease() {
        var m = HotkeyActivationMachine()
        _ = m.handle(.down(at: 1.0), behavior: .holdAndDoubleTap)
        _ = m.handle(.up(at: 1.1), behavior: .holdAndDoubleTap)
        _ = m.handle(.down(at: 2.0), behavior: .holdAndDoubleTap)
        // Long hold then release still stops
        XCTAssertEqual(
            m.handle(.up(at: 2.8), behavior: .holdAndDoubleTap),
            [.stopRecording]
        )
        XCTAssertEqual(m.phase, .idle)
    }

    func testInterruptDuringPendingDoesNotToggle() {
        var m = HotkeyActivationMachine()
        _ = m.handle(.down(at: 1.0), behavior: .holdAndDoubleTap)
        XCTAssertEqual(
            m.handle(.interrupted, behavior: .holdAndDoubleTap),
            [.cancelHoldTimer]
        )
        XCTAssertEqual(m.phase, .idle)
    }

    func testInterruptDuringHoldCancels() {
        var m = HotkeyActivationMachine()
        _ = m.handle(.down(at: 1.0), behavior: .holdAndDoubleTap)
        _ = m.handle(.holdThresholdReached, behavior: .holdAndDoubleTap)
        XCTAssertEqual(
            m.handle(.interrupted, behavior: .holdAndDoubleTap),
            [.cancelRecording]
        )
        XCTAssertEqual(m.phase, .idle)
    }

    func testInterruptDuringHandsFreeStoppingStops() {
        var m = HotkeyActivationMachine()
        _ = m.handle(.down(at: 1.0), behavior: .holdAndDoubleTap)
        _ = m.handle(.up(at: 1.1), behavior: .holdAndDoubleTap)
        _ = m.handle(.down(at: 2.0), behavior: .holdAndDoubleTap)
        XCTAssertEqual(
            m.handle(.interrupted, behavior: .holdAndDoubleTap),
            [.stopRecording]
        )
        XCTAssertEqual(m.phase, .idle)
    }

    // MARK: - Hold only

    func testHoldOnlyLongHoldStops() {
        var m = HotkeyActivationMachine()
        XCTAssertEqual(
            m.handle(.down(at: 1.0), behavior: .holdOnly),
            [.startRecording]
        )
        XCTAssertEqual(
            m.handle(.up(at: 1.6), behavior: .holdOnly),
            [.stopRecording]
        )
    }

    func testHoldOnlyBriefTapCancels() {
        var m = HotkeyActivationMachine()
        _ = m.handle(.down(at: 1.0), behavior: .holdOnly)
        XCTAssertEqual(
            m.handle(.up(at: 1.1), behavior: .holdOnly),
            [.cancelRecording]
        )
    }

    func testHoldOnlyInterruptCancels() {
        var m = HotkeyActivationMachine()
        _ = m.handle(.down(at: 1.0), behavior: .holdOnly)
        XCTAssertEqual(
            m.handle(.interrupted, behavior: .holdOnly),
            [.cancelRecording]
        )
    }

    // MARK: - Toggle

    func testToggleFlips() {
        var m = HotkeyActivationMachine()
        XCTAssertEqual(
            m.handle(.down(at: 1.0), behavior: .toggleOnly),
            [.startRecording]
        )
        XCTAssertEqual(
            m.handle(.down(at: 2.0), behavior: .toggleOnly),
            [.cancelHoldTimer, .stopRecording]
        )
    }
}
