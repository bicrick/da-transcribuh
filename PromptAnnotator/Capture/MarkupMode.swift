import Foundation

/// Capture is the session default: drag a rectangle to snippet the screen.
/// Annotate keeps Shift-to-draw for the pen, highlighter, arrow, rectangle, and text.
enum MarkupMode: Equatable {
    case capture
    case annotate
}
