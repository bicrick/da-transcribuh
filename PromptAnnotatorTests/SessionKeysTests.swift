import CoreGraphics
import XCTest
@testable import PromptAnnotator

/// The hold state machine behind screenshot mode and hold-to-draw.
final class SessionKeysTests: XCTestCase {
    private let keys = SessionKeys.Bindings.standard

    private func hold(
        _ flags: CGEventFlags,
        from current: SessionKeys.Hold = .none,
        bindings: SessionKeys.Bindings? = nil,
        ignoring: CGEventFlags = [],
        suppressed: Bool = false
    ) -> SessionKeys.Hold {
        SessionKeys.hold(
            after: flags,
            current: current,
            bindings: bindings ?? keys,
            ignoring: ignoring,
            suppressed: suppressed
        )
    }

    func testDefaultsAreShiftToGrabAndControlToDraw() {
        XCTAssertEqual(keys.screenshot, .shift)
        XCTAssertEqual(keys.annotate, .control)
    }

    func testShiftAloneStartsScreenshotMode() {
        XCTAssertEqual(hold([.maskShift]), .screenshot)
        XCTAssertEqual(hold([.maskShift, .maskAlphaShift]), .screenshot, "Caps Lock does not count")
    }

    func testControlAloneStartsDrawing() {
        XCTAssertEqual(hold([.maskControl]), .annotate)
    }

    func testCombosStayWithTheirApps() {
        XCTAssertEqual(hold([.maskShift, .maskCommand]), .none, "⌘⇧4 belongs to macOS")
        XCTAssertEqual(hold([.maskShift, .maskAlternate]), .none)
        XCTAssertEqual(hold([.maskControl, .maskCommand]), .none)
        XCTAssertEqual(hold([]), .none)
    }

    func testCommandEndsAScreenshotHold() {
        XCTAssertEqual(hold([.maskShift, .maskCommand], from: .screenshot), .none)
    }

    func testAHoldLastsWhileItsKeyIsDown() {
        XCTAssertEqual(hold([.maskControl, .maskCommand], from: .annotate), .annotate, "⌘Z mid-drawing")
        XCTAssertEqual(hold([.maskShift, .maskAlternate], from: .screenshot), .screenshot)
        XCTAssertEqual(hold([.maskControl], from: .screenshot), .annotate)
        XCTAssertEqual(hold([], from: .screenshot), .none)
        XCTAssertEqual(hold([], from: .annotate), .none)
    }

    func testTypingSuppressesUntilEveryKeyIsUp() {
        XCTAssertEqual(hold([.maskShift], suppressed: true), .none)
        XCTAssertTrue(SessionKeys.stillSuppressed(after: [.maskShift], bindings: keys))
        XCTAssertTrue(SessionKeys.stillSuppressed(after: [.maskControl], bindings: keys))
        XCTAssertFalse(SessionKeys.stillSuppressed(after: [.maskCommand], bindings: keys))
        XCTAssertFalse(SessionKeys.stillSuppressed(after: [], bindings: keys))
    }

    func testPushToTalkModifiersAreIgnoredWhileItsChordIsHeld() {
        XCTAssertEqual(hold([.maskShift, .maskAlternate], ignoring: [.maskAlternate]), .screenshot)
        XCTAssertEqual(hold([.maskShift, .maskCommand], from: .screenshot, ignoring: [.maskCommand]), .screenshot)
    }

    func testRebindingMovesTheHolds() {
        let custom = SessionKeys.Bindings(screenshot: .option, annotate: nil)
        XCTAssertEqual(hold([.maskAlternate], bindings: custom), .screenshot)
        XCTAssertEqual(hold([.maskShift], bindings: custom), .none, "Shift is a normal key again")
        XCTAssertEqual(hold([.maskControl], bindings: custom), .none, "Annotate is Off")
        XCTAssertNil(custom.key(for: .annotate))
        XCTAssertEqual(custom.flags, [.maskAlternate])
    }

    func testAnyKeyEndsAnIdleHold() {
        XCTAssertTrue(SessionKeys.keyEndsHold(.screenshot, gestureInProgress: false))
        XCTAssertTrue(SessionKeys.keyEndsHold(.annotate, gestureInProgress: false))
        XCTAssertFalse(SessionKeys.keyEndsHold(.screenshot, gestureInProgress: true))
        XCTAssertFalse(SessionKeys.keyEndsHold(.none, gestureInProgress: false))
    }

    func testPlainClicksPassThrough() {
        for mode in [MarkupMode.capture, .annotate] {
            XCTAssertEqual(SessionKeys.press(hold: .none, mode: mode, tool: .pen, editing: false), .passThrough)
        }
        XCTAssertEqual(SessionKeys.press(hold: .screenshot, mode: .annotate, tool: .pen, editing: true), .passThrough)
    }

    func testHeldPressesSelectOrDraw() {
        XCTAssertEqual(SessionKeys.press(hold: .screenshot, mode: .capture, tool: .pen, editing: false), .select)
        XCTAssertEqual(SessionKeys.press(hold: .annotate, mode: .annotate, tool: .pen, editing: false), .drawOrClick)
        XCTAssertEqual(SessionKeys.press(hold: .annotate, mode: .annotate, tool: .text, editing: false), .draw)
        XCTAssertEqual(SessionKeys.press(hold: .screenshot, mode: .annotate, tool: .rectangle, editing: false), .drawOrClick)
    }

    func testEdges() {
        XCTAssertEqual(SessionKeys.edge(to: .screenshot, editing: false, gestureInProgress: false), .beginScreenshot)
        XCTAssertEqual(SessionKeys.edge(to: .annotate, editing: false, gestureInProgress: false), .beginAnnotate)
        XCTAssertEqual(SessionKeys.edge(to: .none, editing: false, gestureInProgress: false), .endHold)
        XCTAssertEqual(SessionKeys.edge(to: .none, editing: false, gestureInProgress: true), .finishGestureOnRelease)
        XCTAssertEqual(SessionKeys.edge(to: .screenshot, editing: false, gestureInProgress: true), .keepGesture)
        XCTAssertEqual(SessionKeys.edge(to: .none, editing: true, gestureInProgress: false), .keepEditing)
    }

    func testThresholds() {
        XCTAssertEqual(SessionKeys.drawThreshold, 3)
        XCTAssertGreaterThanOrEqual(CaptureGesture.dragThreshold, 6)
    }

    func testCopyFollowsTheKeys() {
        XCTAssertEqual(keys.grabPhrase, "hold Shift and drag")
        XCTAssertEqual(keys.drawSentence, "Hold Control to draw. Release it to save that tile.")
        let off = SessionKeys.Bindings(screenshot: .shift, annotate: nil)
        XCTAssertTrue(off.drawSentence.hasPrefix("Hold Shift, pick a pen on the bar"))
    }
}

/// The ⌘⇧4-style readout beside the crosshair.
final class ScreenshotBadgeTests: XCTestCase {
    func testPositionAndSizeText() {
        XCTAssertEqual(ScreenshotBadge.position(CGPoint(x: 120.7, y: 44.2)).text, "120, 44")
        let size = ScreenshotBadge.size(of: CGRect(x: 50, y: 50, width: -200.4, height: 80.6), at: .zero)
        XCTAssertEqual(size.text, "200 × 81")
    }

    func testSitsBelowRightOfThePointer() {
        let frame = ScreenshotBadge.position(CGPoint(x: 100, y: 100)).frame(in: CGSize(width: 1000, height: 800))
        XCTAssertEqual(frame.minX, 100 + ScreenshotBadge.offset.width)
        XCTAssertEqual(frame.minY, 100 + ScreenshotBadge.offset.height)
    }

    func testFlipsNearEdgesAndNeverClips() {
        let bounds = CGSize(width: 400, height: 300)
        let corner = ScreenshotBadge.position(CGPoint(x: 395, y: 295)).frame(in: bounds)
        XCTAssertLessThan(corner.maxX, 395)
        XCTAssertLessThan(corner.maxY, 295)
        for point in [CGPoint(x: 0, y: 0), CGPoint(x: 400, y: 0), CGPoint(x: 0, y: 300), CGPoint(x: 400, y: 300)] {
            let frame = ScreenshotBadge.position(point).frame(in: bounds)
            XCTAssertGreaterThanOrEqual(frame.minX, ScreenshotBadge.margin)
            XCTAssertGreaterThanOrEqual(frame.minY, ScreenshotBadge.margin)
            XCTAssertLessThanOrEqual(frame.maxX, bounds.width - ScreenshotBadge.margin)
            XCTAssertLessThanOrEqual(frame.maxY, bounds.height - ScreenshotBadge.margin)
        }
    }

    func testCursorHotSpotIsTheCenter() {
        let cursor = ScreenshotCursor.cursor
        XCTAssertEqual(cursor.hotSpot.x, ScreenshotCursor.size.width / 2)
        XCTAssertEqual(cursor.hotSpot.y, ScreenshotCursor.size.height / 2)
        XCTAssertEqual(cursor.image.size, ScreenshotCursor.size)
    }
}
