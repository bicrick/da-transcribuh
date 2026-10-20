import SwiftUI

enum WaveformSamples {
    static var count: Int { WaveformTrace.columns }
}

/// Thin centered lines. Silence is a dotted baseline. Speech fills the height.
struct WaveformBars: View {
    var levels: [CGFloat]
    var slotWidth: CGFloat = 440
    var slotHeight: CGFloat = 78
    var ink: Color = .primary

    var body: some View {
        Canvas { context, size in
            let bars = columns(for: size.width)
            guard !bars.isEmpty else { return }
            let gap: CGFloat = 1.15
            let barWidth = max(1, (size.width - gap * CGFloat(bars.count - 1)) / CGFloat(bars.count))
            for (index, level) in bars.enumerated() {
                let clamped = min(1, max(0, level))
                let height = max(2, clamped * size.height)
                let x = CGFloat(index) * (barWidth + gap)
                let rect = CGRect(
                    x: x,
                    y: (size.height - height) / 2,
                    width: barWidth,
                    height: height
                )
                let path = Path(roundedRect: rect, cornerRadius: barWidth / 2)
                context.fill(path, with: .color(ink.opacity(0.9)))
            }
        }
        .frame(width: slotWidth, height: slotHeight)
        .accessibilityLabel("Live waveform")
    }

    private func columns(for width: CGFloat) -> [CGFloat] {
        let source = levels.isEmpty ? [WaveformTrace.floor] : levels
        let target = max(12, Int((width / 2.45).rounded()))
        if source.count == target { return source }
        return (0..<target).map { index in
            let start = index * source.count / target
            let end = min(source.count, max(start + 1, (index + 1) * source.count / target))
            return source[start..<end].max() ?? WaveformTrace.floor
        }
    }
}
