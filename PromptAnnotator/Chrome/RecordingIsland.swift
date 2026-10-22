import SwiftUI

struct RecordingIslandView: View {
    @ObservedObject var session: SessionController
    @ObservedObject private var settings = AppSettings.shared
    @ObservedObject private var motion: IslandChromeMotion
    @State private var pulse = false

    init(session: SessionController) {
        self.session = session
        _motion = ObservedObject(wrappedValue: session.islandChrome)
    }

    var body: some View {
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
        // Symmetric: [record + timer] — wave — [chip]. Equal side widths, equal gaps, equal insets.
        return HStack(spacing: 0) {
            leading(layout)
            Color.clear.frame(width: layout.sideGap)
            LiveWaveform(
                display: session.waveform,
                slotWidth: layout.wave.width,
                slotHeight: layout.wave.height,
                ink: Ink.paintCyan
            )
            Color.clear.frame(width: layout.sideGap)
            trailing(layout)
        }
        .padding(.horizontal, IslandMetrics.inset)
        .frame(width: layout.panel.width, height: layout.panel.height)
        .background {
            RoundedRectangle(cornerRadius: Ink.cardRadius, style: .continuous)
                .fill(Ink.window)
                .overlay(
                    RoundedRectangle(cornerRadius: Ink.cardRadius, style: .continuous)
                        .strokeBorder(Ink.hairline, lineWidth: 1)
                )
        }
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
        HStack(spacing: layout.recordClockGap) {
            recordDot
                .opacity(IslandSlots.opacity(for: max(motion.slots.dot, motion.slots.clock)))
            Text(TimeFormat.clock(session.elapsed))
                .font(Ink.mono(IslandMetrics.clockFontSize))
                .monospacedDigit()
                .foregroundStyle(Ink.secondary)
                .lineLimit(1)
                .frame(width: IslandMetrics.fixedClockSpan, alignment: .leading)
                .opacity(IslandSlots.opacity(for: motion.slots.clock))
        }
        .frame(width: layout.side, alignment: .center)
        .frame(minHeight: 28)
        .clipped()
        .accessibilityHidden(max(motion.slots.dot, motion.slots.clock) < 0.05)
    }

    private func trailing(_ layout: IslandLayout) -> some View {
        ZStack {
            CaptureCountChip(count: max(session.captureCount, 1))
                .opacity(IslandSlots.opacity(for: motion.slots.chip))
                .accessibilityHidden(motion.slots.chip < 0.05)
            Text(percentText)
                .font(Ink.mono(IslandMetrics.clockFontSize))
                .monospacedDigit()
                .foregroundStyle(Ink.secondary)
                .lineLimit(1)
                .opacity(IslandSlots.opacity(for: motion.slots.percent))
                .accessibilityHidden(motion.slots.percent < 0.05)
        }
        .frame(width: layout.side, alignment: .center)
        .frame(minHeight: 28)
        .clipped()
    }

    private var percentText: String {
        if case .downloading(let fraction) = session.phase {
            return "\(Int((fraction * 100).rounded()))%"
        }
        return "0%"
    }

    /// Pulsing record marker — flat Paint red square.
    private var recordDot: some View {
        Rectangle()
            .fill(Ink.record)
            .frame(width: IslandMetrics.recordSize, height: IslandMetrics.recordSize)
            .opacity(pulse ? 1 : 0.35)
            .animation(.easeInOut(duration: 0.85).repeatForever(autoreverses: true), value: pulse)
    }
}
