import AppKit

enum ToolCursors {
    static func cursor(for tool: AnnotationTool) -> NSCursor {
        switch tool {
        case .pen: return pen
        case .highlighter: return highlighter
        case .arrow, .rectangle: return .crosshair
        case .text: return .iBeam
        }
    }

    private static let pen: NSCursor = makeCursor(hotSpot: NSPoint(x: 3, y: 3)) { _ in
        let path = NSBezierPath()
        path.move(to: NSPoint(x: 3, y: 3))
        path.line(to: NSPoint(x: 8, y: 6))
        path.line(to: NSPoint(x: 20, y: 18))
        path.line(to: NSPoint(x: 17, y: 21))
        path.line(to: NSPoint(x: 5, y: 9))
        path.close()
        NSColor.white.setStroke()
        path.lineWidth = 3.5
        path.lineJoinStyle = .round
        path.stroke()
        NSColor.black.setFill()
        path.fill()
    }

    private static let highlighter: NSCursor = makeCursor(hotSpot: NSPoint(x: 4, y: 4)) { _ in
        let path = NSBezierPath()
        path.move(to: NSPoint(x: 3, y: 5))
        path.line(to: NSPoint(x: 12, y: 3))
        path.line(to: NSPoint(x: 21, y: 16))
        path.line(to: NSPoint(x: 16, y: 20))
        path.close()
        NSColor.white.setStroke()
        path.lineWidth = 3
        path.stroke()
        NSColor.systemYellow.setFill()
        path.fill()
        NSColor.black.setStroke()
        path.lineWidth = 1
        path.stroke()
    }

    private static func makeCursor(hotSpot: NSPoint, draw: (NSRect) -> Void) -> NSCursor {
        let size = NSSize(width: 24, height: 24)
        let image = NSImage(size: size)
        image.lockFocus()
        draw(NSRect(origin: .zero, size: size))
        image.unlockFocus()
        image.isTemplate = false
        return NSCursor(image: image, hotSpot: hotSpot)
    }
}
