import SwiftUI

/// The snapshot count that slides out beside the clock — Paint tile chip.
struct CaptureCountChip: View {
    var count: Int
    var ink: Color = Ink.label

    var body: some View {
        HStack(spacing: 5) {
            Text("\(count)")
                .font(Ink.mono(13))
                .monospacedDigit()
                .contentTransition(.numericText(value: Double(count)))
            Image(systemName: "photo")
                .font(.system(size: 11, weight: .black))
                .symbolRenderingMode(.monochrome)
        }
        .foregroundStyle(ink)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Ink.window, in: RoundedRectangle(cornerRadius: Ink.buttonRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Ink.buttonRadius, style: .continuous)
                .strokeBorder(Ink.paintOrange, lineWidth: 1.5)
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(count) \(count == 1 ? "capture" : "captures")")
    }
}
