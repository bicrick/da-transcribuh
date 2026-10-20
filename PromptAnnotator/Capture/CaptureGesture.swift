import CoreGraphics

/// Click versus drag for capture mode.
/// A short press is a normal click. A move past `dragThreshold` starts a selection.
enum CaptureGesture {
    /// Points the pointer must travel before a press becomes a snippet drag.
    static let dragThreshold: CGFloat = 6
    /// Both edges must clear this before a drag is saved. A line is not a snippet.
    static let minimumEdge: CGFloat = 4

    static func distance(from start: CGPoint, to end: CGPoint) -> CGFloat {
        hypot(end.x - start.x, end.y - start.y)
    }

    static func isDrag(from start: CGPoint, to end: CGPoint, threshold: CGFloat = dragThreshold) -> Bool {
        distance(from: start, to: end) >= threshold
    }

    /// Display points, origin at the top-left, y down. The rect is normalized.
    static func rect(from start: CGPoint, to end: CGPoint) -> CGRect {
        CGRect(
            x: min(start.x, end.x),
            y: min(start.y, end.y),
            width: abs(end.x - start.x),
            height: abs(end.y - start.y)
        )
    }

    static func isCapturable(_ rect: CGRect, minimumEdge: CGFloat = minimumEdge) -> Bool {
        let box = rect.standardized
        return box.width >= minimumEdge && box.height >= minimumEdge
    }
}
