import SwiftUI

enum WaveformSamples {
    static let count = 19
}

/// Frequency bars. Each one stays in its slot and changes height with the sound.
struct WaveformBars: View {
    var levels: [CGFloat]
    var slotWidth: CGFloat = 188
    var slotHeight: CGFloat = 26

    var body: some View {
        let bars = levels.isEmpty ? [CGFloat(0.12)] : levels
        HStack(alignment: .center, spacing: spacing(for: bars.count)) {
            ForEach(Array(bars.enumerated()), id: \.offset) { _, level in
                Capsule(style: .continuous)
                    .fill(Color.primary.opacity(0.82))
                    .frame(width: Self.barWidth, height: barHeight(level))
            }
        }
        .frame(width: slotWidth, height: slotHeight)
        .animation(.easeOut(duration: 0.1), value: levels)
    }

    private func barHeight(_ level: CGFloat) -> CGFloat {
        let clamped = min(1, max(0, level))
        return max(3, 3 + clamped * (slotHeight - 3))
    }

    private func spacing(for count: Int) -> CGFloat {
        guard count > 1 else { return 0 }
        let used = CGFloat(count) * Self.barWidth
        let raw = (slotWidth - used) / CGFloat(count - 1)
        return min(6, max(2, raw))
    }

    private static let barWidth: CGFloat = 3.5
}
