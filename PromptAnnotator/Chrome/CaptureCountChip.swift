import SwiftUI

/// The snapshot count that slides out beside the clock.
struct CaptureCountChip: View {
    var count: Int
    var ink: Color = Ink.label

    var body: some View {
        HStack(spacing: 5) {
            Text("\(count)")
                .font(Ink.labelFont)
                .monospacedDigit()
                .contentTransition(.numericText(value: Double(count)))
            Image(systemName: "photo")
                .font(Ink.buttonSmallFont)
        }
        .foregroundStyle(ink)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Ink.window)
        .overlay(
            RoundedRectangle(cornerRadius: Ink.buttonRadius, style: .continuous)
                .strokeBorder(ink, lineWidth: 1)
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(count) \(count == 1 ? "capture" : "captures")")
    }
}
