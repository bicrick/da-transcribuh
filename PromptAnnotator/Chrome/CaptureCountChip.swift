import SwiftUI

/// The snapshot count that slides out beside the clock.
struct CaptureCountChip: View {
    var count: Int
    var ink: Color = .primary

    var body: some View {
        HStack(spacing: 5) {
            Text("\(count)")
                .font(.system(size: 13, weight: .semibold).monospacedDigit())
                .contentTransition(.numericText(value: Double(count)))
            Image(systemName: "photo")
                .font(.system(size: 12, weight: .medium))
        }
        .foregroundStyle(ink)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(ink.opacity(0.08))
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(count) \(count == 1 ? "capture" : "captures")")
    }
}
