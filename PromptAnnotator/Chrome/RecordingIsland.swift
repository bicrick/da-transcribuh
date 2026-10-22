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
        // Hard offset shadow is drawn inside the panel (ChromePanel masksToBounds).
        // Content footprint stays the same; shadow room is added in islandPanelSize().
        return HStack(spacing: 0) {
            leading(layout)
            LiveWaveform(
                display: session.waveform,
                slotWidth: layout.wave.width,
                slotHeight: layout.wave.height,
                ink: Ink.paintCyan
            )
            trailing(layout)
        }
        .padding(.horizontal, IslandMetrics.inset)
        .frame(width: layout.panel.width, height: layout.panel.height)
        .overlay(alignment: .bottomLeading) {
            miniPalette
                .padding(.leading, IslandMetrics.inset)
                .padding(.bottom, 3)
        }
        .background {
            RoundedRectangle(cornerRadius: Ink.cardRadius, style: .continuous)
                .fill(Ink.label)
                .offset(x: Ink.buttonShadow, y: Ink.buttonShadow)
            RoundedRectangle(cornerRadius: Ink.cardRadius, style: .continuous)
                .fill(Ink.window)
                .overlay(
                    RoundedRectangle(cornerRadius: Ink.cardRadius, style: .continuous)
                        .strokeBorder(Ink.label, lineWidth: 1.5)
                )
        }
        .padding(.trailing, Ink.buttonShadow)
        .padding(.bottom, Ink.buttonShadow)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(islandAccessibilityLabel)
        .onAppear { pulse = true }
    }

    /// Tiny Paint swatch strip — decorative, no layout cost.
    private var miniPalette: some View {
        HStack(spacing: 1) {
            miniSwatch(Ink.paintRed)
            miniSwatch(Ink.paintYellow)
            miniSwatch(Ink.paintLime)
            miniSwatch(Ink.paintBlue)
        }
        .accessibilityHidden(true)
    }

    private func miniSwatch(_ color: Color) -> some View {
        Rectangle()
            .fill(color)
            .frame(width: 5, height: 5)
            .overlay(Rectangle().strokeBorder(Ink.label, lineWidth: 0.5))
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
        HStack(spacing: 0) {
            label(layout)
            dot(layout)
            Color.clear.frame(width: layout.leadingGap)
        }
        .frame(width: layout.side, alignment: .trailing)
        .clipped()
    }

    private func trailing(_ layout: IslandLayout) -> some View {
        HStack(spacing: 0) {
            Color.clear.frame(width: layout.trailingGap)
            clock(layout)
            Color.clear.frame(width: layout.clockChipGap)
            chip(layout)
            Color.clear.frame(width: layout.chipPercentGap)
            percent(layout)
        }
        .frame(width: layout.side, alignment: .leading)
        .clipped()
    }

    private func label(_ layout: IslandLayout) -> some View {
        HStack(spacing: 8) {
            recordDot
            Text("Recording")
                .font(Ink.labelFont)
                .foregroundStyle(Ink.label)
                .lineLimit(1)
        }
        .fixedSize()
        .frame(width: layout.label, alignment: .trailing)
        .clipped()
        .opacity(IslandSlots.opacity(for: motion.slots.label))
        .accessibilityHidden(motion.slots.label < 0.05)
    }

    private func dot(_ layout: IslandLayout) -> some View {
        recordDot
            .frame(width: layout.dot, alignment: .center)
            .clipped()
            .opacity(IslandSlots.opacity(for: motion.slots.dot))
            .accessibilityHidden(motion.slots.dot < 0.05)
    }

    private func clock(_ layout: IslandLayout) -> some View {
        Text(TimeFormat.clock(session.elapsed))
            .font(Ink.mono(13))
            .foregroundStyle(Ink.secondary)
            .lineLimit(1)
            .fixedSize()
            .frame(width: layout.clock, alignment: .leading)
            .clipped()
            .opacity(IslandSlots.opacity(for: motion.slots.clock))
            .accessibilityHidden(motion.slots.clock < 0.05)
    }

    private func chip(_ layout: IslandLayout) -> some View {
        CaptureCountChip(count: max(session.captureCount, 1))
            .fixedSize()
            .frame(width: layout.chip, alignment: .leading)
            .clipped()
            .opacity(IslandSlots.opacity(for: motion.slots.chip))
            .accessibilityHidden(motion.slots.chip < 0.05)
    }

    private func percent(_ layout: IslandLayout) -> some View {
        Text(percentText)
            .font(Ink.mono(11))
            .foregroundStyle(Ink.secondary)
            .lineLimit(1)
            .fixedSize()
            .frame(width: layout.percent, alignment: .leading)
            .clipped()
            .opacity(IslandSlots.opacity(for: motion.slots.percent))
            .accessibilityHidden(motion.slots.percent < 0.05)
    }

    private var percentText: String {
        if case .downloading(let fraction) = session.phase {
            return "\(Int((fraction * 100).rounded()))%"
        }
        return "0%"
    }

    /// Pulsing record marker — flat Paint red square (same 8pt footprint).
    private var recordDot: some View {
        Rectangle()
            .fill(Ink.record)
            .overlay(Rectangle().strokeBorder(Ink.label, lineWidth: 1))
            .frame(width: 8, height: 8)
            .opacity(pulse ? 1 : 0.35)
            .animation(.easeInOut(duration: 0.85).repeatForever(autoreverses: true), value: pulse)
    }
}
