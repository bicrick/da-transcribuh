import SwiftUI

/// Single clean square “dt” mark with a hard Paint-color offset shadow.
/// Replaces the doubled squircle-in-a-box AppMark treatment in chrome footers.
struct InkDtMark: View {
    var side: CGFloat = 28
    var shadow: Color = Ink.paintRed

    var body: some View {
        Text("dt")
            .font(Ink.mono(side * 0.42))
            .foregroundStyle(Ink.paintBlack)
            .frame(width: side, height: side)
            .background(Ink.paintWhite)
            .overlay(
                Rectangle()
                    .strokeBorder(Ink.label, lineWidth: 1.5)
            )
            .background(
                Rectangle()
                    .fill(shadow)
                    .offset(x: Ink.buttonShadow, y: Ink.buttonShadow)
            )
            .accessibilityLabel("da transcribuh")
    }
}
