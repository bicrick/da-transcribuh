import SwiftUI

/// Modifier scalars Departure Mono does not include. ⌘ and ⌥ are in the face;
/// ⇧ / ⌃ / ⌫ are not, and `Text` draws them as tofu (`.notdef`).
enum InkMissingGlyph: String, Equatable {
    case shift = "\u{21E7}"
    case control = "\u{2303}"
    case delete = "\u{232B}"

    init?(_ label: String) {
        switch label {
        case Self.shift.rawValue: self = .shift
        case Self.control.rawValue: self = .control
        case Self.delete.rawValue: self = .delete
        default: return nil
        }
    }
}

/// Stroke-drawn stand-in, same idea as `ClipboardSearchGlyph`.
struct InkMissingGlyphView: View {
    var glyph: InkMissingGlyph

    var body: some View {
        Canvas { context, size in
            let stroke = max(1.15, min(size.width, size.height) * 0.14)
            var path = Path()
            switch glyph {
            case .shift:
                let mid = size.width / 2
                let head = size.height * 0.46
                let stem = size.width * 0.16
                path.move(to: CGPoint(x: mid, y: stroke))
                path.addLine(to: CGPoint(x: size.width - stroke, y: head))
                path.addLine(to: CGPoint(x: mid + stem, y: head))
                path.addLine(to: CGPoint(x: mid + stem, y: size.height - stroke))
                path.addLine(to: CGPoint(x: mid - stem, y: size.height - stroke))
                path.addLine(to: CGPoint(x: mid - stem, y: head))
                path.addLine(to: CGPoint(x: stroke, y: head))
                path.closeSubpath()
            case .control:
                path.move(to: CGPoint(x: stroke, y: size.height * 0.68))
                path.addLine(to: CGPoint(x: size.width / 2, y: size.height * 0.22))
                path.addLine(to: CGPoint(x: size.width - stroke, y: size.height * 0.68))
            case .delete:
                let midY = size.height * 0.52
                path.move(to: CGPoint(x: size.width - stroke, y: midY))
                path.addLine(to: CGPoint(x: size.width * 0.42, y: midY))
                path.move(to: CGPoint(x: size.width * 0.55, y: size.height * 0.28))
                path.addLine(to: CGPoint(x: stroke * 1.4, y: midY))
                path.addLine(to: CGPoint(x: size.width * 0.55, y: size.height * 0.76))
            }
            context.stroke(
                path,
                with: .foreground,
                style: StrokeStyle(lineWidth: stroke, lineCap: .square, lineJoin: .miter)
            )
        }
        .accessibilityHidden(true)
    }
}

/// Departure Mono for covered characters; drawn glyphs for ⇧ / ⌃ / ⌫.
struct InkGlyphString: View {
    var text: String
    var size: CGFloat = 11
    var color: Color = Ink.label

    var body: some View {
        HStack(alignment: .center, spacing: 0) {
            ForEach(Array(Self.pieces(text).enumerated()), id: \.offset) { _, piece in
                switch piece {
                case .plain(let value):
                    Text(value)
                        .font(Ink.mono(size))
                        .foregroundStyle(color)
                case .glyph(let glyph):
                    InkMissingGlyphView(glyph: glyph)
                        .frame(width: size * 0.95, height: size)
                        .foregroundStyle(color)
                }
            }
        }
        .fixedSize(horizontal: true, vertical: true)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(text)
    }

    enum Piece: Equatable {
        case plain(String)
        case glyph(InkMissingGlyph)
    }

    static func pieces(_ text: String) -> [Piece] {
        var result: [Piece] = []
        var plain = ""
        for character in text {
            let token = String(character)
            if let glyph = InkMissingGlyph(token) {
                if !plain.isEmpty {
                    result.append(.plain(plain))
                    plain = ""
                }
                result.append(.glyph(glyph))
            } else {
                plain.append(character)
            }
        }
        if !plain.isEmpty {
            result.append(.plain(plain))
        }
        return result
    }
}
