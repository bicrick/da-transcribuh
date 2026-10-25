import AppKit

/// The screenshot-mode pointer: a thin ⌘⇧4-style crosshair with a white halo,
/// so it reads on light and dark pages alike. The hot spot is the exact center.
enum ScreenshotCursor {
    static let size = NSSize(width: 27, height: 27)
    /// Arms stop short of the center, so the pixel under the hot spot stays visible.
    static let gap: CGFloat = 2.5
    static let arm: CGFloat = 12

    static let cursor: NSCursor = {
        NSCursor(image: image(), hotSpot: NSPoint(x: size.width / 2, y: size.height / 2))
    }()

    static func image() -> NSImage {
        let image = NSImage(size: size, flipped: false) { rect in
            draw(in: rect)
            return true
        }
        image.isTemplate = false
        return image
    }

    static func draw(in rect: NSRect) {
        let center = NSPoint(x: rect.midX, y: rect.midY)
        let path = NSBezierPath()
        for (dx, dy) in [(1.0, 0.0), (-1.0, 0.0), (0.0, 1.0), (0.0, -1.0)] {
            path.move(to: NSPoint(x: center.x + dx * gap, y: center.y + dy * gap))
            path.line(to: NSPoint(x: center.x + dx * arm, y: center.y + dy * arm))
        }
        path.lineCapStyle = .square
        NSColor.white.withAlphaComponent(0.92).setStroke()
        path.lineWidth = 3
        path.stroke()
        NSColor.black.setStroke()
        path.lineWidth = 1
        path.stroke()

        let dot = NSBezierPath(ovalIn: NSRect(x: center.x - 1, y: center.y - 1, width: 2, height: 2))
        NSColor.white.withAlphaComponent(0.92).setStroke()
        dot.lineWidth = 1.5
        dot.stroke()
        NSColor.black.setFill()
        dot.fill()
    }
}

/// The live readout beside the screenshot crosshair. Before a drag it shows where the
/// pointer is. During a drag it shows the size of the box. Points are display-local
/// with the origin at the top left, the same numbers ⌘⇧4 shows.
struct ScreenshotBadge: Equatable {
    var text: String
    /// Pointer position, display-local, origin top left.
    var anchor: CGPoint

    static func position(_ point: CGPoint) -> ScreenshotBadge {
        ScreenshotBadge(text: "\(Int(point.x.rounded(.down))), \(Int(point.y.rounded(.down)))", anchor: point)
    }

    static func size(of rect: CGRect, at point: CGPoint) -> ScreenshotBadge {
        let box = rect.standardized
        return ScreenshotBadge(
            text: "\(Int(box.width.rounded())) × \(Int(box.height.rounded()))",
            anchor: point
        )
    }

    /// Distance from the pointer to the badge's near corner.
    static let offset = CGSize(width: 16, height: 18)
    static let padding = CGSize(width: 7, height: 4)
    static let margin: CGFloat = 6

    static var font: NSFont {
        NSFont(name: Ink.monoName, size: 11) ?? .monospacedSystemFont(ofSize: 11, weight: .medium)
    }

    func textSize() -> CGSize {
        let measured = (text as NSString).size(withAttributes: [.font: Self.font])
        return CGSize(width: ceil(measured.width), height: ceil(measured.height))
    }

    /// Badge frame in display-local, top-left coordinates. Sits below and right of the
    /// pointer and flips to the other side near a screen edge so it never clips.
    func frame(in bounds: CGSize) -> CGRect {
        let inner = textSize()
        let width = inner.width + Self.padding.width * 2
        let height = inner.height + Self.padding.height * 2
        var x = anchor.x + Self.offset.width
        var y = anchor.y + Self.offset.height
        if x + width > bounds.width - Self.margin {
            x = anchor.x - Self.offset.width - width
        }
        if y + height > bounds.height - Self.margin {
            y = anchor.y - Self.offset.height - height
        }
        x = min(max(Self.margin, x), max(Self.margin, bounds.width - width - Self.margin))
        y = min(max(Self.margin, y), max(Self.margin, bounds.height - height - Self.margin))
        return CGRect(x: x.rounded(), y: y.rounded(), width: width, height: height)
    }
}
