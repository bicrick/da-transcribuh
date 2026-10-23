import Foundation

/// Sort order for the history list (Maccy Storage).
enum ClipboardSortMode: String, CaseIterable, Identifiable, Codable {
    case lastCopy
    case firstCopy
    case copyCount

    var id: String { rawValue }

    var title: String {
        switch self {
        case .lastCopy: return "Time of last copy"
        case .firstCopy: return "Time of first copy"
        case .copyCount: return "Number of copies"
        }
    }
}

/// Where the history panel appears (Maccy Appearance).
enum ClipboardPopupPosition: String, CaseIterable, Identifiable, Codable {
    case cursor
    case menuBar
    case screenCenter

    var id: String { rawValue }

    var title: String {
        switch self {
        case .cursor: return "At cursor"
        case .menuBar: return "Near menu bar icon"
        case .screenCenter: return "Screen center"
        }
    }
}

enum ClipboardPinEdge: String, CaseIterable, Identifiable, Codable {
    case top
    case bottom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .top: return "Pin to top"
        case .bottom: return "Pin to bottom"
        }
    }
}
