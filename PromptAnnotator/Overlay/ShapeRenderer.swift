import AppKit
import CoreText

/// Draws annotation shapes in a y-down point space (origin at the top-left).
enum ShapeRenderer {
    static func draw(
        shapes: [AnnotationShape],
        draft: AnnotationShape?,
        textEdit: TextEdit?,
        caretOn: Bool,
        in context: CGContext
    ) {
        for shape in shapes where shape.isSignificant() {
            draw(shape, in: context)
        }
        if let draft {
            draw(draft, in: context)
        }
        if let textEdit {
            drawEditor(textEdit, caretOn: caretOn, in: context)
        }
    }

    /// Paints `base` and then the shapes. `pointSize` is the display size in points;
    /// shape coordinates are top-left, y down, in that space.
    static func composite(
        base: CGImage,
        shapes: [AnnotationShape],
        pointSize: CGSize
    ) -> CGImage? {
        let pixelWidth = base.width
        let pixelHeight = base.height
        guard pixelWidth > 0, pixelHeight > 0, pointSize.width > 0, pointSize.height > 0 else {
            return nil
        }
        guard let context = CGContext(
            data: nil,
            width: pixelWidth,
            height: pixelHeight,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }

        context.draw(base, in: CGRect(x: 0, y: 0, width: pixelWidth, height: pixelHeight))
        context.saveGState()
        context.translateBy(x: 0, y: CGFloat(pixelHeight))
        context.scaleBy(
            x: CGFloat(pixelWidth) / pointSize.width,
            y: -CGFloat(pixelHeight) / pointSize.height
        )
        draw(shapes: shapes, draft: nil, textEdit: nil, caretOn: false, in: context)
        context.restoreGState()
        return context.makeImage()
    }

    private static func draw(_ shape: AnnotationShape, in context: CGContext) {
        switch shape.tool {
        case .pen:
            stroke(
                path: linePath(shape.points),
                color: shape.color,
                width: InkStyle.penWidth,
                halo: InkStyle.penHalo,
                alpha: 1,
                in: context
            )
        case .highlighter:
            stroke(
                path: linePath(shape.points),
                color: shape.color,
                width: InkStyle.highlighterWidth,
                halo: 0,
                alpha: InkStyle.highlighterAlpha,
                in: context
            )
        case .arrow:
            drawArrow(shape, in: context)
        case .rectangle:
            guard shape.points.count >= 2 else { return }
            let rect = rect(from: shape.points[0], to: shape.points[shape.points.count - 1])
            stroke(
                path: CGPath(rect: rect, transform: nil),
                color: shape.color,
                width: InkStyle.lineWidth,
                halo: InkStyle.lineHalo,
                alpha: 1,
                in: context
            )
        case .text:
            guard let text = shape.text, let origin = shape.points.first else { return }
            drawLabel(text, at: origin, color: shape.color, in: context)
        }
    }

    private static func drawArrow(_ shape: AnnotationShape, in context: CGContext) {
        guard let start = shape.points.first, let end = shape.points.last, start != end else { return }
        let angle = atan2(end.y - start.y, end.x - start.x)
        let headLength = InkStyle.arrowHeadLength
        let headWidth = InkStyle.arrowHeadWidth
        let shaftEnd = CGPoint(
            x: end.x - cos(angle) * headLength * 0.72,
            y: end.y - sin(angle) * headLength * 0.72
        )
        let shaft = CGMutablePath()
        shaft.move(to: start)
        shaft.addLine(to: shaftEnd)

        let base = CGPoint(
            x: end.x - cos(angle) * headLength,
            y: end.y - sin(angle) * headLength
        )
        let left = CGPoint(
            x: base.x + (-sin(angle)) * headWidth / 2,
            y: base.y + cos(angle) * headWidth / 2
        )
        let right = CGPoint(
            x: base.x - (-sin(angle)) * headWidth / 2,
            y: base.y - cos(angle) * headWidth / 2
        )
        let head = CGMutablePath()
        head.move(to: end)
        head.addLine(to: left)
        head.addLine(to: right)
        head.closeSubpath()

        stroke(
            path: shaft,
            color: shape.color,
            width: InkStyle.lineWidth,
            halo: InkStyle.lineHalo,
            alpha: 1,
            in: context
        )
        context.saveGState()
        context.setFillColor(haloColor(for: shape.color).cgColor)
        context.addPath(head)
        context.fillPath()
        context.setFillColor(shape.color.nsColor.cgColor)
        // Inset the colored head slightly so the halo reads as an edge.
        context.translateBy(x: end.x, y: end.y)
        context.scaleBy(x: 0.82, y: 0.82)
        context.translateBy(x: -end.x, y: -end.y)
        context.addPath(head)
        context.fillPath()
        context.restoreGState()
    }

    private static func stroke(
        path: CGPath?,
        color: InkColor,
        width: CGFloat,
        halo: CGFloat,
        alpha: CGFloat,
        in context: CGContext
    ) {
        guard let path else { return }
        context.saveGState()
        context.setLineCap(.round)
        context.setLineJoin(.round)
        if halo > 0 {
            context.setStrokeColor(haloColor(for: color).cgColor)
            context.setLineWidth(width + halo)
            context.addPath(path)
            context.strokePath()
        }
        context.setStrokeColor(color.nsColor.withAlphaComponent(alpha).cgColor)
        context.setLineWidth(width)
        context.addPath(path)
        context.strokePath()
        context.restoreGState()
    }

    private static func linePath(_ points: [CGPoint]) -> CGPath? {
        guard let first = points.first else { return nil }
        let path = CGMutablePath()
        path.move(to: first)
        if points.count == 1 {
            path.addLine(to: CGPoint(x: first.x + 0.1, y: first.y))
        } else {
            for point in points.dropFirst() {
                path.addLine(to: point)
            }
        }
        return path
    }

    private static func rect(from start: CGPoint, to end: CGPoint) -> CGRect {
        CGRect(
            x: min(start.x, end.x),
            y: min(start.y, end.y),
            width: abs(end.x - start.x),
            height: abs(end.y - start.y)
        )
    }

    private static func haloColor(for color: InkColor) -> NSColor {
        if color.isNearWhite {
            return NSColor.black.withAlphaComponent(0.55)
        }
        return NSColor.white.withAlphaComponent(0.92)
    }

    private static func labelFont() -> NSFont {
        NSFont.systemFont(ofSize: InkStyle.fontSize, weight: .semibold)
    }

    private static func drawLabel(_ text: String, at origin: CGPoint, color: InkColor, in context: CGContext) {
        let font = labelFont()
        let halo = NSAttributedString(
            string: text,
            attributes: [
                .font: font,
                .foregroundColor: haloColor(for: color),
                .strokeColor: haloColor(for: color),
                .strokeWidth: 8,
            ]
        )
        let fill = NSAttributedString(
            string: text,
            attributes: [
                .font: font,
                .foregroundColor: color.nsColor,
            ]
        )
        context.saveGState()
        context.translateBy(x: origin.x, y: origin.y + font.ascender)
        context.scaleBy(x: 1, y: -1)
        CTLineDraw(CTLineCreateWithAttributedString(halo), context)
        CTLineDraw(CTLineCreateWithAttributedString(fill), context)
        context.restoreGState()
    }

    private static func drawEditor(_ edit: TextEdit, caretOn: Bool, in context: CGContext) {
        let font = labelFont()
        let textWidth = (edit.text as NSString).size(withAttributes: [.font: font]).width
        let box = CGRect(
            x: edit.origin.x,
            y: edit.origin.y,
            width: max(140, textWidth + 24),
            height: 32
        )
        context.saveGState()
        context.setFillColor(NSColor.black.withAlphaComponent(0.55).cgColor)
        let path = CGPath(roundedRect: box, cornerWidth: 6, cornerHeight: 6, transform: nil)
        context.addPath(path)
        context.fillPath()
        context.restoreGState()

        if !edit.text.isEmpty {
            drawLabel(edit.text, at: CGPoint(x: edit.origin.x + 8, y: edit.origin.y + 4), color: edit.color, in: context)
        }
        if caretOn {
            let caret = CGRect(
                x: edit.origin.x + 8 + textWidth + 1,
                y: edit.origin.y + 6,
                width: 1.5,
                height: 20
            )
            context.setFillColor(edit.color.nsColor.cgColor)
            context.fill(caret)
        }
    }
}
