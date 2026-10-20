import XCTest
@testable import PromptAnnotator

final class ShiftAnnotationTests: XCTestCase {
    func testShiftHeldSelectionStaysASelection() {
        XCTAssertEqual(
            ShiftAnnotation.press(mode: .capture, shiftDown: true, editing: false),
            .select
        )
        XCTAssertEqual(
            ShiftAnnotation.shiftEdge(down: true, editing: false, selecting: true, stroking: false),
            .keepSelecting
        )
    }

    func testDrawingToolsRequireShiftAndDoNotStealAReleasedClick() {
        XCTAssertEqual(
            ShiftAnnotation.press(mode: .annotate, shiftDown: true, editing: false),
            .draw
        )
        XCTAssertEqual(
            ShiftAnnotation.press(mode: .annotate, shiftDown: false, editing: false),
            .passThrough
        )
        XCTAssertEqual(
            ShiftAnnotation.press(mode: .capture, shiftDown: false, editing: false),
            .select
        )
    }

    func testOpenLabelIgnoresShiftAndClicks() {
        XCTAssertEqual(
            ShiftAnnotation.press(mode: .annotate, shiftDown: true, editing: true),
            .passThrough
        )
        XCTAssertEqual(
            ShiftAnnotation.shiftEdge(down: false, editing: true, selecting: false, stroking: false),
            .keepEditing
        )
        XCTAssertEqual(
            ShiftAnnotation.shiftEdge(down: true, editing: true, selecting: false, stroking: false),
            .keepEditing
        )
    }

    func testReleasingShiftSavesOnlyWhenNothingIsInProgress() {
        XCTAssertEqual(
            ShiftAnnotation.shiftEdge(down: false, editing: false, selecting: false, stroking: false),
            .endHold
        )
        XCTAssertEqual(
            ShiftAnnotation.shiftEdge(down: false, editing: false, selecting: false, stroking: true),
            .finishGestureOnRelease
        )
        XCTAssertEqual(
            ShiftAnnotation.shiftEdge(down: false, editing: false, selecting: true, stroking: false),
            .finishGestureOnRelease
        )
    }
}
