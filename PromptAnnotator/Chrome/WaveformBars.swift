import SwiftUI

enum WaveformSamples {
    /// One stationary slot per pitch. Dense enough to read as a comb, cheap enough to update in place.
    static let count = 64
}

/// Thin centered lines. Each one stays in its slot and only changes height.
struct WaveformBars: View {
    var levels: [CGFloat]
    var slotWidth: CGFloat = 210
    var slotHeight: CGFloat = 26
    var ink: Color = .primary

    var body: some View {
        Canvas { context, size in
            let bars = levels.isEmpty ? [CGFloat(0.1)] : levels
            let count = bars.count
            guard count > 0, size.width > 1, size.height > 1 else { return }
            let gap = count > 24 ? CGFloat(1.15) : CGFloat(2)
            let barWidth = max(1, (size.width - gap * CGFloat(count - 1)) / CGFloat(count))
            for index in 0..<count {
                let level = min(1, max(0, bars[index]))
                let height = max(2, 2 + level * (size.height - 2))
                let rect = CGRect(
                    x: CGFloat(index) * (barWidth + gap),
                    y: (size.height - height) / 2,
                    width: barWidth,
                    height: height
                )
                let path = Path(roundedRect: rect, cornerRadius: min(1, barWidth / 2))
                context.fill(path, with: .color(ink.opacity(0.88)))
            }
        }
        .frame(width: slotWidth, height: slotHeight)
        .accessibilityLabel("Live waveform")
    }
}
