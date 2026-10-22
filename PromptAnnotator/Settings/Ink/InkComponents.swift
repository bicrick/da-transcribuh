import SwiftUI

// MARK: - Card / Tile

struct InkCard<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Ink.card, in: RoundedRectangle(cornerRadius: Ink.cardRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Ink.cardRadius, style: .continuous)
                .strokeBorder(Ink.hairline, lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.05), radius: 7, x: 0, y: 4)
    }
}

struct InkTile<Content: View>: View {
    var selected: Bool = false
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: Ink.tileRadius, style: .continuous)
                        .fill(Ink.card)
                    if selected {
                        RoundedRectangle(cornerRadius: Ink.tileRadius, style: .continuous)
                            .fill(Ink.accentSoft)
                    }
                }
            )
            .overlay(
                RoundedRectangle(cornerRadius: Ink.tileRadius, style: .continuous)
                    .strokeBorder(selected ? Ink.accent : Ink.hairline, lineWidth: selected ? 2 : 1)
            )
            .shadow(color: Color.black.opacity(selected ? 0.08 : 0.05), radius: selected ? 10 : 7, x: 0, y: 4)
    }
}

// MARK: - Typography / section

struct InkSectionHeader: View {
    var title: String
    var caption: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(Ink.sectionTitleFont)
                .foregroundStyle(Ink.label)
            if let caption {
                Text(caption)
                    .font(Ink.captionFont)
                    .foregroundStyle(Ink.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

struct InkEyebrow: View {
    var text: String

    var body: some View {
        Text(text.uppercased())
            .font(Ink.eyebrowFont)
            .tracking(0.6)
            .foregroundStyle(Ink.accent)
    }
}

struct InkBadge: View {
    var text: String
    var accented: Bool = false

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(accented ? Ink.accent : Ink.secondary)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(
                (accented ? Ink.accentSoft : Ink.fill),
                in: Capsule(style: .continuous)
            )
    }
}

struct InkDivider: View {
    var leading: CGFloat = Ink.rowHPad

    var body: some View {
        Rectangle()
            .fill(Ink.hairline)
            .frame(height: 1)
            .padding(.leading, leading)
    }
}

struct InkIconChip: View {
    var systemName: String
    var tint: Color = Ink.label

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(tint)
            .frame(width: 30, height: 30)
            .background(Ink.fill, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

// MARK: - Controls

struct InkKeycap: View {
    var label: String
    var compact: Bool = false

    var body: some View {
        Text(label)
            .font(.system(size: compact ? 12 : 15, weight: .semibold))
            .foregroundStyle(Ink.label)
            .padding(.horizontal, compact ? 6 : 10)
            .frame(minWidth: compact ? 22 : 34, minHeight: compact ? 22 : 34)
            .background(Ink.keycap, in: RoundedRectangle(cornerRadius: compact ? 6 : Ink.keycapRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: compact ? 6 : Ink.keycapRadius, style: .continuous)
                    .strokeBorder(Ink.borderStrong, lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.06), radius: 2, x: 0, y: 1)
    }
}

struct InkKeycapRow: View {
    var keys: [String]
    var compact: Bool = false

    var body: some View {
        HStack(spacing: compact ? 4 : 6) {
            ForEach(Array(keys.enumerated()), id: \.offset) { _, key in
                InkKeycap(label: key, compact: compact)
            }
        }
    }
}

/// 10-segment meter for Speed / Quality / Size.
struct InkSegmentMeter: View {
    var label: String
    var fraction: Double
    var emphasized: Bool = false
    private let segments = 10

    var body: some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(Ink.secondary)
                .frame(width: 48, alignment: .leading)
            HStack(spacing: 3) {
                ForEach(0..<segments, id: \.self) { index in
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(index < litCount ? (emphasized ? Ink.accent : Ink.meter) : Ink.track)
                        .frame(height: 5)
                }
            }
        }
    }

    private var litCount: Int {
        let clamped = min(1, max(0, fraction))
        return max(1, Int((clamped * Double(segments)).rounded()))
    }
}

struct InkProgressBar: View {
    var fraction: Double

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule(style: .continuous)
                    .fill(Ink.track)
                Capsule(style: .continuous)
                    .fill(Ink.accent)
                    .frame(width: max(4, geo.size.width * min(1, max(0, fraction))))
            }
        }
        .frame(height: 6)
    }
}

struct InkRadio: View {
    var selected: Bool

    var body: some View {
        ZStack {
            Circle()
                .strokeBorder(selected ? Ink.accent : Ink.tertiary, lineWidth: selected ? 0 : 1.5)
                .background(Circle().fill(selected ? Ink.accent : Color.clear))
            if selected {
                Circle()
                    .fill(Ink.onAccent)
                    .frame(width: 7, height: 7)
            }
        }
        .frame(width: 18, height: 18)
    }
}

struct InkCheck: View {
    var done: Bool

    var body: some View {
        ZStack {
            Circle()
                .fill(done ? Ink.accent : Color.clear)
            if done {
                Image(systemName: "checkmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(Ink.onAccent)
            } else {
                Circle()
                    .strokeBorder(Ink.tertiary, lineWidth: 1.5)
            }
        }
        .frame(width: 20, height: 20)
    }
}

struct InkStepDots: View {
    var current: Int
    var total: Int

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<total, id: \.self) { index in
                if index == current {
                    Capsule(style: .continuous)
                        .fill(Ink.accent)
                        .frame(width: 22, height: 6)
                } else {
                    Circle()
                        .fill(Ink.track)
                        .frame(width: 6, height: 6)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Step \(current + 1) of \(total)")
    }
}

struct InkPrimaryButtonStyle: ButtonStyle {
    var large: Bool = true
    var enabled: Bool = true

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(enabled ? Ink.onAccent : Ink.accent.opacity(0.75))
            .padding(.horizontal, large ? 16 : 11)
            .frame(height: large ? 32 : 24)
            .background(
                (enabled ? Ink.accent : Ink.accentSoft),
                in: RoundedRectangle(
                    cornerRadius: large ? Ink.buttonLargeRadius : Ink.buttonRadius,
                    style: .continuous
                )
            )
            .opacity(configuration.isPressed ? 0.88 : 1)
    }
}

struct InkSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(Ink.label)
            .padding(.horizontal, 11)
            .frame(height: 24)
            .background(Ink.card, in: RoundedRectangle(cornerRadius: Ink.buttonRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Ink.buttonRadius, style: .continuous)
                    .strokeBorder(Ink.borderStrong, lineWidth: 1)
            )
            .opacity(configuration.isPressed ? 0.85 : 1)
    }
}

struct InkFieldBackground: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .background(Ink.field, in: RoundedRectangle(cornerRadius: Ink.fieldRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Ink.fieldRadius, style: .continuous)
                    .strokeBorder(Ink.borderStrong, lineWidth: 1)
            )
    }
}

extension View {
    func inkFieldStyle() -> some View {
        modifier(InkFieldBackground())
    }

    func inkPageChrome() -> some View {
        self
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Ink.window)
            .tint(Ink.accent)
    }
}

/// Welcome / Ready motif: waveform bars taper into ONE continuous left-to-right red ink stroke ending at a pen tip (no U-shaped "smile" under the bars).
struct InkWavePenMotif: View {
    var inked: Bool = false
    var width: CGFloat = 360
    var height: CGFloat = 140

    private let barCount = 22

    var body: some View {
        Canvas { context, size in
            let barColor = inked ? Ink.accent : Ink.label
            let inkColor = Ink.accent
            let penColor = Ink.label

            let midY = size.height * 0.48
            let barRegionWidth = size.width * 0.46
            let barMaxH = size.height * 0.46
            let gap: CGFloat = 3
            let barW = max(2, (barRegionWidth - gap * CGFloat(barCount - 1)) / CGFloat(barCount))
            let originX: CGFloat = 16

            var join = CGPoint(x: originX, y: midY)
            for i in 0..<barCount {
                let t = Double(i) / Double(max(barCount - 1, 1))
                // Soft wave envelope that narrows into the ink stroke on the right.
                let envelope = 0.28 + 0.72 * sin(t * .pi * 0.95)
                let taper = 1.0 - pow(t, 1.35) * 0.78
                let h = max(2.5, barMaxH * envelope * taper)
                let x = originX + CGFloat(i) * (barW + gap)
                let rect = CGRect(x: x, y: midY - h / 2, width: barW, height: h)
                context.fill(
                    Path(roundedRect: rect, cornerRadius: barW / 2),
                    with: .color(barColor)
                )
                join = CGPoint(x: rect.maxX + 1, y: midY)
            }

            // Fountain pen tip on the right; ink line stays near midY (gently wavy, not a U-curve).
            let tip = CGPoint(x: size.width - 28, y: midY + 6)
            let penTop = CGPoint(x: tip.x, y: midY - 40)

            var ink = Path()
            ink.move(to: join)
            ink.addCurve(
                to: tip,
                control1: CGPoint(x: join.x + (tip.x - join.x) * 0.35, y: midY - 4),
                control2: CGPoint(x: join.x + (tip.x - join.x) * 0.72, y: midY + 8)
            )
            context.stroke(
                ink,
                with: .color(inkColor),
                style: StrokeStyle(lineWidth: 7, lineCap: .round, lineJoin: .round)
            )

            // Pen body: slight tilt toward the tip.
            var penBody = Path()
            penBody.move(to: CGPoint(x: penTop.x - 5, y: penTop.y))
            penBody.addLine(to: CGPoint(x: penTop.x + 5, y: penTop.y))
            penBody.addLine(to: CGPoint(x: tip.x + 4, y: tip.y - 10))
            penBody.addLine(to: CGPoint(x: tip.x - 4, y: tip.y - 10))
            penBody.closeSubpath()
            context.fill(penBody, with: .color(penColor))

            var nib = Path()
            nib.move(to: CGPoint(x: tip.x - 5, y: tip.y - 10))
            nib.addLine(to: CGPoint(x: tip.x + 5, y: tip.y - 10))
            nib.addLine(to: tip)
            nib.closeSubpath()
            context.fill(nib, with: .color(inkColor))
        }
        .frame(width: width, height: height)
        .accessibilityHidden(true)
    }
}

// Spec aliases used in the Ink design brief.
typealias MeterBar = InkSegmentMeter
typealias Keycap = InkKeycap
typealias StepDots = InkStepDots
typealias SectionHeader = InkSectionHeader

struct InkErrorBanner: View {
    var message: String

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Ink.error)
            Text(message)
                .font(Ink.captionFont)
                .foregroundStyle(Ink.error)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(Ink.error.opacity(0.10), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Ink.error.opacity(0.35), lineWidth: 1)
        )
    }
}

struct InkDashedEmpty: View {
    var title: String
    var detail: String
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(Ink.rowTitleFont)
                .foregroundStyle(Ink.label)
            Text(detail)
                .font(Ink.captionFont)
                .foregroundStyle(Ink.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(InkSecondaryButtonStyle())
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(
            RoundedRectangle(cornerRadius: Ink.cardRadius, style: .continuous)
                .strokeBorder(Ink.borderStrong, style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
        )
    }
}
