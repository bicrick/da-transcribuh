import Foundation

/// Capture: a drag with the screenshot key held snippets the screen.
/// Annotate draws with the pen, highlighter, arrow, rectangle, and text.
/// See `SessionKeys` for which held key selects which mode.
enum MarkupMode: Equatable {
    case capture
    case annotate
}
