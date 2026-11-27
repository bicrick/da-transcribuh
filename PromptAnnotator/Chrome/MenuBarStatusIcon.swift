import AppKit

/// Renders the `dt` menu-bar icon with a color + badge state when Stay Awake is active.
///
/// - `.inactive`: callers use the standard template `MenuBarIcon` asset (monochrome, adapts to menu bar).
/// - `.lidClosed`: vivid Paint Orange `dt` + top-right indicator dot (unmistakable on light & dark menu bars).
/// - `.lidOpen`: vivid Paint Green `dt` + top-right indicator dot.
enum MenuBarStatusIcon {
    static let activeCanvasSize = NSSize(width: 21, height: 16)
    static let iconDrawRect = NSRect(x: 0, y: 0, width: 16, height: 16)
    static let badgeRect = NSRect(x: 16.5, y: 10.0, width: 4, height: 4)

    /// Returns a non-template, appearance-adaptive `NSImage` for active Stay Awake states,
    /// or `nil` when `.inactive` (use stock template `Image("MenuBarIcon")`).
    static func image(for state: StayAwakeIndicatorState, baseIcon: NSImage? = NSImage(named: "MenuBarIcon")) -> NSImage? {
        guard state != .inactive, let baseIcon else { return nil }
        let copy = baseIcon.copy() as? NSImage ?? baseIcon
        copy.isTemplate = false
        let img = NSImage(size: activeCanvasSize, flipped: false) { _ in
            drawActive(state: state, baseIcon: copy)
            return true
        }
        img.isTemplate = false
        return img
    }

    /// Renders a concrete bitmap for deterministic unit tests and snapshot verification.
    static func renderBitmap(
        for state: StayAwakeIndicatorState,
        darkMenuBar: Bool,
        scale: Int = 2,
        baseIcon: NSImage? = NSImage(named: "MenuBarIcon")
    ) -> NSBitmapImageRep? {
        guard state != .inactive, let baseIcon else { return nil }
        let copy = baseIcon.copy() as? NSImage ?? baseIcon
        copy.isTemplate = false
        let widthPx = Int(activeCanvasSize.width) * scale
        let heightPx = Int(activeCanvasSize.height) * scale
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: widthPx,
            pixelsHigh: heightPx,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .calibratedRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else { return nil }
        rep.size = activeCanvasSize

        NSGraphicsContext.saveGraphicsState()
        guard let ctx = NSGraphicsContext(bitmapImageRep: rep) else {
            NSGraphicsContext.restoreGraphicsState()
            return nil
        }
        NSGraphicsContext.current = ctx
        let appearance = NSAppearance(named: darkMenuBar ? .darkAqua : .aqua)
        appearance?.performAsCurrentDrawingAppearance {
            drawActive(state: state, baseIcon: copy)
        }
        NSGraphicsContext.restoreGraphicsState()
        return rep
    }

    private static func drawActive(state: StayAwakeIndicatorState, baseIcon: NSImage) {
        let isDark = NSAppearance.currentDrawing()
            .bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let tint = tintColor(for: state, darkMenuBar: isDark)

        // Draw tinted `dt` mark inside `iconDrawRect` via an offscreen mask pass so alpha stays crisp.
        if let tinted = tintedCopy(of: baseIcon, color: tint, size: iconDrawRect.size) {
            tinted.draw(
                in: iconDrawRect,
                from: .zero,
                operation: .sourceOver,
                fraction: 1.0
            )
        }

        // Crisp status dot badge on the upper-right so even colorblind users see a shape change.
        let haloColor: NSColor = isDark
            ? NSColor(srgbRed: 0, green: 0, blue: 0, alpha: 0.45)
            : NSColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.65)
        haloColor.setFill()
        NSBezierPath(ovalIn: badgeRect.insetBy(dx: -0.75, dy: -0.75)).fill()

        tint.setFill()
        NSBezierPath(ovalIn: badgeRect).fill()
    }

    private static func tintedCopy(of source: NSImage, color: NSColor, size: NSSize) -> NSImage? {
        let out = NSImage(size: size, flipped: false) { rect in
            source.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1.0)
            color.setFill()
            rect.fill(using: .sourceAtop)
            return true
        }
        out.isTemplate = false
        return out
    }

    static func tintColor(for state: StayAwakeIndicatorState, darkMenuBar: Bool) -> NSColor {
        switch state {
        case .lidClosed:
            // Classic Paint Orange lifted slightly for dark menu bars, deepened for light menu bars.
            return darkMenuBar
                ? Ink.nsColor(hex: "#FF922B")
                : Ink.nsColor(hex: "#D95300")
        case .lidOpen:
            // Classic Paint Green adapted for menu-bar contrast.
            return darkMenuBar
                ? Ink.nsColor(hex: "#3FD06A")
                : Ink.nsColor(hex: "#15803D")
        case .inactive:
            return .labelColor
        }
    }
}
