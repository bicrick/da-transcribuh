import SwiftUI

/// Snapshot count beside the waveform — flat hairline chip. Sizes follow the island scale.
struct CaptureCountChip: View {
    var count: Int
    var ink: Color = Ink.label
    var fontSize: CGFloat = IslandMetrics.chipFontSize
    var iconSize: CGFloat = IslandMetrics.chipIconSize
    var minHeight: CGFloat = 28

    var body: some View {
        HStack(spacing: Ink.space1 + 2) {
            Text("\(count)")
                .font(Ink.mono(fontSize))
                .monospacedDigit()
                .contentTransition(.numericText(value: Double(count)))
            Image(systemName: "photo")
                .font(.system(size: iconSize, weight: .black))
                .symbolRenderingMode(.monochrome)
        }
        .foregroundStyle(ink)
        .padding(.horizontal, minHeight >= 28 ? Ink.space2 : Ink.space1 + 2)
        .padding(.vertical, Ink.space1)
        .frame(minHeight: minHeight)
        .background(Ink.front, in: RoundedRectangle(cornerRadius: Ink.buttonRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Ink.buttonRadius, style: .continuous)
                .strokeBorder(Ink.label, lineWidth: Ink.stroke)
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(count) \(count == 1 ? "capture" : "captures")")
    }
}
