import XCTest
@testable import PromptAnnotator

final class HotkeyActivationMachineTests: XCTestCase {
    func testHoldAndDoubleTapLongHoldStops() {
        var m = HotkeyActivationMachine()
        XCTAssertEqual(
            m.handle(.down(at: 1.0), behavior: .holdAndDoubleTap),
            [.startRecording]
        )
        XCTAssertEqual(
            m.handle(.up(at: 1.6), behavior: .holdAndDoubleTap),
            [.stopRecording]
        )
    }

    func testHoldAndDoubleTapBriefTapArmsTimerThenCancels() {
        var m = HotkeyActivationMachine()
        _ = m.handle(.down(at: 1.0), behavior: .holdAndDoubleTap)
        let up = m.handle(.up(at: 1.2), behavior: .holdAndDoubleTap)
        XCTAssertEqual(up, [.armDoubleTapTimer(deadline: 1.7)])
        XCTAssertEqual(
            m.handle(.doubleTapTimedOut, behavior: .holdAndDoubleTap),
            [.cancelRecording]
        )
    }

    func testHoldAndDoubleTapSecondTapHandsFree() {
        var m = HotkeyActivationMachine()
        _ = m.handle(.down(at: 1.0), behavior: .holdAndDoubleTap)
        _ = m.handle(.up(at: 1.2), behavior: .holdAndDoubleTap)
        XCTAssertEqual(
            m.handle(.down(at: 1.4), behavior: .holdAndDoubleTap),
            [.cancelDoubleTapTimer]
        )
        // Stop hands-free with a press+release
        XCTAssertEqual(
            m.handle(.up(at: 1.5), behavior: .holdAndDoubleTap),
            []
        )
        // Still hands-free until stopping press
        _ = m.handle(.down(at: 3.0), behavior: .holdAndDoubleTap)
        XCTAssertEqual(
            m.handle(.up(at: 3.6), behavior: .holdAndDoubleTap),
            [.stopRecording]
        )
    }

    func testHoldAndDoubleTapInterruptCancels() {
        var m = HotkeyActivationMachine()
        _ = m.handle(.down(at: 1.0), behavior: .holdAndDoubleTap)
        XCTAssertEqual(
            m.handle(.interrupted, behavior: .holdAndDoubleTap),
            [.cancelDoubleTapTimer, .cancelRecording]
        )
    }

    func testHoldOnlyBriefCancels() {
        var m = HotkeyActivationMachine()
        _ = m.handle(.down(at: 1.0), behavior: .holdOnly)
        XCTAssertEqual(
            m.handle(.up(at: 1.2), behavior: .holdOnly),
            [.cancelRecording]
        )
    }

    func testToggleOnlyIgnoresUp() {
        var m = HotkeyActivationMachine()
        XCTAssertEqual(
            m.handle(.down(at: 1.0), behavior: .toggleOnly),
            [.startRecording]
        )
        XCTAssertEqual(m.handle(.up(at: 1.1), behavior: .toggleOnly), [])
        XCTAssertEqual(
            m.handle(.down(at: 2.0), behavior: .toggleOnly),
            [.cancelDoubleTapTimer, .stopRecording]
        )
    }
}
