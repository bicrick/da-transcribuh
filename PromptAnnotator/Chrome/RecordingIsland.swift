import SwiftUI

struct RecordingIslandView: View {
    @ObservedObject var session: SessionController
    @ObservedObject private var settings = AppSettings.shared
    @ObservedObject private var motion: IslandChromeMotion
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulse = false

    init(session: SessionController) {
        self.session = session
        _motion = ObservedObject(wrappedValue: session.islandChrome)
    }

    var body: some View {
        let _ = PerfSuite.count("island")
        Group {
            if motion.presence != .hidden {
                island
            }
        }
    }

    private var island: some View {
        let layout = IslandMetrics.layout(
            style: settings.islandStyle,
            slots: motion.slots,
            captures: session.captureCount,
            elapsed: session.elapsed
        )
        let scale = layout.scale
        // [record + timer] — wave — [chip?]. Double-pane matches selected chrome / InkDtMark bevel.
        return HStack(spacing: 0) {
            leading(layout)
            Color.clear.frame(width: layout.sideGapLeading)
            LiveWaveform(
                display: session.waveform,
                slotWidth: layout.wave.width,
                slotHeight: layout.wave.height,
                ink: Ink.label
            )
            Color.clear.frame(width: layout.sideGapTrailing)
            trailing(layout)
        }
        .padding(.horizontal, scale.inset)
        .frame(width: layout.panel.width, height: layout.panel.height)
        .inkDoublePane(cornerRadius: Ink.cardRadius, fill: Ink.front)
        // Hits stay on the bar face — not the down-right pane gutter.
        .contentShape(
            Path(CGRect(x: 0, y: 0, width: layout.panel.width, height: layout.panel.height))
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(islandAccessibilityLabel)
        .onAppear { pulse = true }
    }

    private var islandAccessibilityLabel: String {
        let status = session.statusText.isEmpty ? "da transcribuh" : session.statusText
        if session.phase == .recording {
            let time = TimeFormat.clock(session.elapsed)
            let captures = session.captureCount
            if captures > 0 {
                return "\(status), \(time), \(captures) \(captures == 1 ? "capture" : "captures")"
            }
            return "\(status), \(time)"
        }
        return status
    }

    private func leading(_ layout: IslandLayout) -> some View {
        let scale = layout.scale
        return HStack(spacing: layout.recordClockGap) {
            recordDot(size: scale.recordSize)
                .opacity(IslandSlots.opacity(for: max(motion.slots.dot, motion.slots.clock)))
            Text(TimeFormat.clock(session.elapsed))
                .font(Ink.mono(scale.clockFontSize))
                .monospacedDigit()
                .foregroundStyle(Ink.secondary)
                .lineLimit(1)
                .frame(width: scale.clockSpan, alignment: .leading)
                .opacity(IslandSlots.opacity(for: motion.slots.clock))
        }
        .frame(width: layout.leadingSide, alignment: .center)
        .frame(minHeight: scale.chipMinHeight)
        .clipped()
        .accessibilityHidden(max(motion.slots.dot, motion.slots.clock) < 0.05)
    }

    private func trailing(_ layout: IslandLayout) -> some View {
        let scale = layout.scale
        let chipOpen = motion.slots.chip
        let percentOpen = motion.slots.percent
        return ZStack {
            CaptureCountChip(
                count: max(session.captureCount, 1),
                fontSize: scale.chipFontSize,
                iconSize: scale.chipIconSize,
                minHeight: scale.chipMinHeight
            )
            .scaleEffect(reduceMotion ? 1 : (0.88 + 0.12 * chipOpen))
            .opacity(IslandSlots.opacity(for: chipOpen))
            .accessibilityHidden(chipOpen < 0.05)

            Text(percentText)
                .font(Ink.mono(scale.clockFontSize))
                .monospacedDigit()
                .foregroundStyle(Ink.secondary)
                .lineLimit(1)
                .opacity(IslandSlots.opacity(for: percentOpen))
                .accessibilityHidden(percentOpen < 0.05)
        }
        .frame(width: layout.trailingSide, alignment: .center)
        .frame(minHeight: scale.chipMinHeight)
        .clipped()
    }

    private var percentText: String {
        if case .downloading(let fraction) = session.phase {
            return "\(Int((fraction * 100).rounded()))%"
        }
        return "0%"
    }

    private func recordDot(size: CGFloat) -> some View {
        Rectangle()
            .fill(Ink.record)
            .frame(width: size, height: size)
            .opacity(pulse ? 1 : 0.35)
            .animation(.easeInOut(duration: 0.85).repeatForever(autoreverses: true), value: pulse)
    }
}
