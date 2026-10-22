import SwiftUI

/// Snapshot count beside the waveform — flat hairline chip, ≥28pt hit height.
struct CaptureCountChip: View {
    var count: Int
    var ink: Color = Ink.label

    var body: some View {
        HStack(spacing: Ink.space1 + 2) {
            Text("\(count)")
                .font(Ink.mono(IslandMetrics.chipFontSize))
                .monospacedDigit()
                .contentTransition(.numericText(value: Double(count)))
            Image(systemName: "photo")
                .font(.system(size: IslandMetrics.chipIconSize, weight: .black))
                .symbolRenderingMode(.monochrome)
        }
        .foregroundStyle(ink)
        .padding(.horizontal, Ink.space2)
        .padding(.vertical, Ink.space1 + 2)
        .frame(minHeight: 28)
        .background(Ink.window, in: RoundedRectangle(cornerRadius: Ink.buttonRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Ink.buttonRadius, style: .continuous)
                .strokeBorder(Ink.hairline, lineWidth: 1)
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(count) \(count == 1 ? "capture" : "captures")")
    }
}
