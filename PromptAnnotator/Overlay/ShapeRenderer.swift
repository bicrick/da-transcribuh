import AppKit
import CoreText

/// Draws annotation shapes in a y-down point space (origin at the top-left).
enum ShapeRenderer {
    /// Head length as a fraction of the whole arrow. A short drag stays in front of its start.
    private static let arrowHeadShare: CGFloat = 0.42

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
                alpha: 1,
                cap: .round,
                join: .round,
                in: context
            )
        case .highlighter:
            stroke(
                path: linePath(shape.points),
                color: shape.color,
                width: InkStyle.highlighterWidth,
                alpha: InkStyle.highlighterAlpha,
                cap: .round,
                join: .round,
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
                alpha: 1,
                cap: .butt,
                join: .miter,
                in: context
            )
        case .text:
            guard let text = shape.text, let origin = shape.points.first else { return }
            drawLabel(text, at: origin, color: shape.color, in: context)
        }
    }

    private static func drawArrow(_ shape: AnnotationShape, in context: CGContext) {
        guard let start = shape.points.first, let end = shape.points.last, start != end else { return }
        let dx = end.x - start.x
        let dy = end.y - start.y
        let length = hypot(dx, dy)
        guard length >= 1 else { return }

        let angle = atan2(dy, dx)
        let scale = min(1, length / (InkStyle.arrowHeadLength / arrowHeadShare))
        let headLength = InkStyle.arrowHeadLength * scale
        let headWidth = InkStyle.arrowHeadWidth * scale
        let width = max(1.5, InkStyle.lineWidth * scale)
        let ux = cos(angle)
        let uy = sin(angle)

        let overlap = min(width * 0.55, headLength * 0.35)
        let shaftLength = max(0, length - headLength + overlap)
        if shaftLength > 0.5 {
            let shaftEnd = CGPoint(x: start.x + ux * shaftLength, y: start.y + uy * shaftLength)
            let shaft = CGMutablePath()
            shaft.move(to: start)
            shaft.addLine(to: shaftEnd)
            stroke(
                path: shaft,
                color: shape.color,
                width: width,
                alpha: 1,
                cap: .round,
                join: .round,
                in: context
            )
        }

        let base = CGPoint(x: end.x - ux * headLength, y: end.y - uy * headLength)
        let left = CGPoint(
            x: base.x + (-uy) * headWidth / 2,
            y: base.y + ux * headWidth / 2
        )
        let right = CGPoint(
            x: base.x - (-uy) * headWidth / 2,
            y: base.y - ux * headWidth / 2
        )
        let head = CGMutablePath()
        head.move(to: end)
        head.addLine(to: left)
        head.addLine(to: right)
        head.closeSubpath()

        context.saveGState()
        context.setFillColor(shape.color.nsColor.cgColor)
        context.addPath(head)
        context.fillPath()
        context.restoreGState()
    }

    private static func stroke(
        path: CGPath?,
        color: InkColor,
        width: CGFloat,
        alpha: CGFloat,
        cap: CGLineCap,
        join: CGLineJoin,
        in context: CGContext
    ) {
        guard let path else { return }
        context.saveGState()
        context.setLineCap(cap)
        context.setLineJoin(join)
        context.setMiterLimit(2)
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

    private static func labelFont() -> NSFont {
        FontMetrics.font(size: InkStyle.fontSize, weight: .semibold)
    }

    private static func drawLabel(_ text: String, at origin: CGPoint, color: InkColor, in context: CGContext) {
        let font = labelFont()
        let fill = NSAttributedString(
            string: text,
            attributes: [
                .font: font,
                .foregroundColor: color.nsColor,
            ]
        )
        context.saveGState()
        context.setShouldSmoothFonts(false)
        context.translateBy(x: origin.x, y: origin.y + font.ascender)
        context.scaleBy(x: 1, y: -1)
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

        let glyph = CGPoint(
            x: edit.origin.x + InkStyle.textPadX,
            y: edit.origin.y + InkStyle.textPadY
        )
        if !edit.text.isEmpty {
            drawLabel(edit.text, at: glyph, color: edit.color, in: context)
        }
        if caretOn {
            let caret = CGRect(
                x: glyph.x + textWidth + 1,
                y: edit.origin.y + 6,
                width: 1.5,
                height: 20
            )
            context.setFillColor(edit.color.nsColor.cgColor)
            context.fill(caret)
        }
    }
}
