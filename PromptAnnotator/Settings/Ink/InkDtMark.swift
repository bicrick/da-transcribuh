import SwiftUI

/// Chosen brand mark: Departure Mono lowercase “d” + inverted “t” (white on black block),
/// inside a white square with a black hard-offset bevel (same double-pane language as tiles / island).
/// Dark mode keeps the tile white with a black bevel so the mark stays constant across themes.
struct InkDtMark: View {
    var side: CGFloat = 28

    private var gap: CGFloat { max(1, side * 0.04) }
    private var fontSize: CGFloat { side * 0.46 }
    private var pad: CGFloat { side * 0.14 }
    private var bevel: CGFloat { max(1.5, side * (Ink.buttonShadow / 28)) }

    var body: some View {
        mark
            .padding(pad)
            .frame(width: side, height: side)
            .background(Color.white)
            .overlay(
                Rectangle()
                    .strokeBorder(Color.black, lineWidth: max(1, side * 0.04))
            )
            .background(
                Rectangle()
                    .fill(Color.black)
                    .offset(x: bevel, y: bevel)
            )
            .accessibilityLabel("da transcribuh")
    }

    private var mark: some View {
        HStack(spacing: gap) {
            Text("d")
                .font(Ink.mono(fontSize))
                .foregroundStyle(Color.black)
            Text("t")
                .font(Ink.mono(fontSize))
                .foregroundStyle(Color.white)
                .padding(.horizontal, fontSize * 0.12)
                .padding(.vertical, fontSize * 0.02)
                .background(Color.black)
        }
        .fixedSize()
    }
}
