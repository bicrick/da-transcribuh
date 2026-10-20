import Foundation

/// Pointer and Shift decisions for a session.
/// Selection stays a selection while Shift is held, and a text label outlives Shift.
enum ShiftAnnotation {
    enum Press: Equatable {
        /// The page underneath receives the click.
        case passThrough
        /// A drag snippets the screen. A click that does not move is replayed.
        case select
        /// Pen, highlighter, arrow, rectangle, or text.
        case draw
    }

    enum ShiftEdge: Equatable {
        /// Shift is only changing a capital letter. The open label stays put.
        case keepEditing
        /// A snippet is already being dragged. Do not turn it into a stroke.
        case keepSelecting
        /// Shift went down with no snippet in progress. Draw with the armed tool.
        case beginDrawing
        /// Shift came up in the middle of a stroke or a snippet. The mouse-up finishes it.
        case finishGestureOnRelease
        /// Shift came up with nothing in progress. Save the marks and go back to clicks.
        case endHold
    }

    static func press(mode: MarkupMode, shiftDown: Bool, editing: Bool) -> Press {
        if editing { return .passThrough }
        if mode == .capture { return .select }
        if shiftDown { return .draw }
        return .passThrough
    }

    static func shiftEdge(down: Bool, editing: Bool, selecting: Bool, stroking: Bool) -> ShiftEdge {
        if editing { return .keepEditing }
        if down && selecting { return .keepSelecting }
        if down { return .beginDrawing }
        if stroking || selecting { return .finishGestureOnRelease }
        return .endHold
    }
}
