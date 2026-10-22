import AppKit

enum AnnotationTool: String, Codable, CaseIterable, Equatable {
    case pen
    case highlighter
    case arrow
    case rectangle
    case text

    var title: String {
        switch self {
        case .pen: return "Pen"
        case .highlighter: return "Highlighter"
        case .arrow: return "Arrow"
        case .rectangle: return "Rectangle"
        case .text: return "Text"
        }
    }

    var symbolName: String {
        switch self {
        case .pen: return "pencil.tip"
        case .highlighter: return "highlighter"
        case .arrow: return "arrow.up.right"
        case .rectangle: return "rectangle"
        case .text: return "character.cursor.ibeam"
        }
    }
}

struct InkColor: Codable, Equatable, Hashable {
    var name: String
    var red: Double
    var green: Double
    var blue: Double

    var hex: String {
        String(
            format: "#%02X%02X%02X",
            Int((red * 255).rounded()),
            Int((green * 255).rounded()),
            Int((blue * 255).rounded())
        )
    }

    var nsColor: NSColor {
        NSColor(srgbRed: red, green: green, blue: blue, alpha: 1)
    }

    var swiftUIRed: Double { red }
    var swiftUIGreen: Double { green }
    var swiftUIBlue: Double { blue }

    var isNearWhite: Bool { red + green + blue > 2.7 }

    static let red = InkColor(name: "red", red: 0.86, green: 0.15, blue: 0.15)
    static let orange = InkColor(name: "orange", red: 0.95, green: 0.45, blue: 0.13)
    static let yellow = InkColor(name: "yellow", red: 0.96, green: 0.76, blue: 0.12)
    static let green = InkColor(name: "green", red: 0.16, green: 0.62, blue: 0.28)
    static let blue = InkColor(name: "blue", red: 0.16, green: 0.42, blue: 0.86)
    static let white = InkColor(name: "white", red: 1, green: 1, blue: 1)

    static let palette: [InkColor] = [.red, .orange, .yellow, .green, .blue, .white]
}

enum InkStyle {
    static let penWidth: CGFloat = 7
    static let highlighterWidth: CGFloat = 32
    static let highlighterAlpha: CGFloat = 0.35
    static let lineWidth: CGFloat = 6
    static let fontSize: CGFloat = 22
    static let minimumDistance: CGFloat = 4
    static let arrowHeadLength: CGFloat = 18
    static let arrowHeadWidth: CGFloat = 14
    /// Inset of the glyphs inside the live text field. Committed labels use the same origin.
    static let textPadX: CGFloat = 8
    static let textPadY: CGFloat = 4
}

struct AnnotationShape: Identifiable, Equatable {
    var id: UUID
    var tool: AnnotationTool
    var color: InkColor
    var points: [CGPoint]
    var text: String?

    func isSignificant(threshold: CGFloat = InkStyle.minimumDistance) -> Bool {
        switch tool {
        case .text:
            let trimmed = (text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            return !trimmed.isEmpty
        case .pen, .highlighter, .arrow, .rectangle:
            guard let first = points.first else { return false }
            return points.contains { point in
                hypot(point.x - first.x, point.y - first.y) >= threshold
            }
        }
    }

    var bounds: CGRect {
        if tool == .text, let text, let origin = points.first {
            let font = FontMetrics.font(size: InkStyle.fontSize, weight: .semibold)
            let size = (text as NSString).size(withAttributes: [.font: font])
            return CGRect(origin: origin, size: size)
        }
        guard let first = points.first else { return .zero }
        var rect = CGRect(origin: first, size: .zero)
        for point in points.dropFirst() {
            rect = rect.union(CGRect(origin: point, size: .zero))
        }
        return rect
    }
}

struct TextEdit: Equatable {
    var origin: CGPoint
    var text: String
    var color: InkColor

    func shape() -> AnnotationShape {
        let glyph = CGPoint(x: origin.x + InkStyle.textPadX, y: origin.y + InkStyle.textPadY)
        return AnnotationShape(id: UUID(), tool: .text, color: color, points: [glyph], text: text)
    }
}

struct DisplaySnapshot: Codable, Equatable {
    var id: UInt32
    var widthPoints: Double
    var heightPoints: Double
    var widthPixels: Int
    var heightPixels: Int
    var frameX: Double
    var frameY: Double
    var frameWidth: Double
    var frameHeight: Double

    init(screen: NSScreen, pixelWidth: Int, pixelHeight: Int, contentSize: CGSize? = nil) {
        id = ScreenGeometry.displayID(of: screen) ?? 0
        if let contentSize {
            widthPoints = Double(contentSize.width)
            heightPoints = Double(contentSize.height)
        } else {
            widthPoints = Double(screen.frame.width)
            heightPoints = Double(screen.frame.height)
        }
        widthPixels = pixelWidth
        heightPixels = pixelHeight
        frameX = Double(screen.frame.origin.x)
        frameY = Double(screen.frame.origin.y)
        frameWidth = Double(screen.frame.width)
        frameHeight = Double(screen.frame.height)
    }
}

struct PointRecord: Codable, Equatable {
    var x: Double
    var y: Double
}

struct RectRecord: Codable, Equatable {
    var x: Double
    var y: Double
    var width: Double
    var height: Double

    init(_ rect: CGRect) {
        x = Double(rect.origin.x)
        y = Double(rect.origin.y)
        width = Double(rect.size.width)
        height = Double(rect.size.height)
    }
}

struct ShapeRecord: Codable, Equatable {
    var id: UUID
    var tool: String
    var color: String
    var colorName: String
    var points: [PointRecord]
    var text: String?
    var bounds: RectRecord

    init(_ shape: AnnotationShape) {
        id = shape.id
        tool = shape.tool.rawValue
        color = shape.color.hex
        colorName = shape.color.name
        points = shape.points.map { PointRecord(x: Double($0.x), y: Double($0.y)) }
        text = shape.text
        bounds = RectRecord(shape.bounds)
    }
}
