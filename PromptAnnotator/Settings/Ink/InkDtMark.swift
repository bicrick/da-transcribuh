import SwiftUI

/// Chosen brand mark: Departure Mono lowercase “d” + inverted “t” block,
/// inside a square with a hard-offset bevel (same double-pane language as tiles / island).
/// Light: white tile, black ink. Dark: graphite tile, light ink (inverts with the theme).
struct InkDtMark: View {
    var side: CGFloat = 28

    private var gap: CGFloat { max(1, side * 0.04) }
    private var fontSize: CGFloat { side * 0.46 }
    private var pad: CGFloat { side * 0.14 }
    private var bevel: CGFloat { Ink.bevelOffset }

    var body: some View {
        mark
            .padding(pad)
            .frame(width: side, height: side)
            .background(Ink.markFace)
            .overlay(
                Rectangle()
                    .strokeBorder(Ink.markInk, lineWidth: Ink.stroke)
            )
            .background(
                Rectangle()
                    .fill(Ink.bevel)
                    .offset(x: bevel, y: bevel)
            )
            .accessibilityLabel("da transcribuh")
    }

    private var mark: some View {
        HStack(spacing: gap) {
            Text("d")
                .font(Ink.mono(fontSize))
                .foregroundStyle(Ink.markInk)
            Text("t")
                .font(Ink.mono(fontSize))
                .foregroundStyle(Ink.markInvertInk)
                .padding(.horizontal, fontSize * 0.12)
                .padding(.vertical, fontSize * 0.02)
                .background(Ink.markInvertFace)
        }
        .fixedSize()
    }
}
