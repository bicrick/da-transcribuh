import SwiftUI

struct RecordingIslandView: View {
    @ObservedObject var session: SessionController
    @ObservedObject private var settings = AppSettings.shared
    @ObservedObject private var motion: IslandChromeMotion

    init(session: SessionController) {
        self.session = session
        _motion = ObservedObject(wrappedValue: session.islandChrome)
    }

    var body: some View {
        bodyContent.focusEffectDisabled()
    }

    @ViewBuilder private var bodyContent: some View {
        let _ = PerfSuite.count("island")
        Group {
            if motion.presence != .hidden {
                RecordingIslandFace(
                    style: settings.islandStyle,
                    slots: motion.slots,
                    captures: session.captureCount,
                    elapsed: session.elapsed,
                    percentText: percentText
                ) { width, height in
                    LiveWaveform(
                        display: session.waveform,
                        slotWidth: width,
                        slotHeight: height,
                        ink: Ink.label
                    )
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(islandAccessibilityLabel)
            }
        }
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

    private var percentText: String {
        if case .downloading(let fraction) = session.phase {
            return "\(Int((fraction * 100).rounded()))%"
        }
        return "0%"
    }
}

/// The island's face, fed plain values. The live island binds it to the session;
/// onboarding feeds it a fixed demo state so the welcome step shows the real chrome.
struct RecordingIslandFace<Wave: View>: View {
    var style: IslandStyle
    var slots: IslandSlots
    var captures: Int
    var elapsed: TimeInterval
    var percentText: String = "0%"
    /// The live island pulses its record square. A static demo holds it solid.
    var pulses: Bool = true
    @ViewBuilder var wave: (CGFloat, CGFloat) -> Wave

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulse = false

    var body: some View {
        let layout = IslandMetrics.layout(
            style: style,
            slots: slots,
            captures: captures,
            elapsed: elapsed
        )
        let scale = layout.scale
        // [record + timer] — wave — [chip?]. Double-pane matches selected chrome / InkDtMark bevel.
        return HStack(spacing: 0) {
            leading(layout)
            Color.clear.frame(width: layout.sideGapLeading)
            wave(layout.wave.width, layout.wave.height)
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
        .onAppear { if pulses { pulse = true } }
    }

    private func leading(_ layout: IslandLayout) -> some View {
        let scale = layout.scale
        return HStack(spacing: layout.recordClockGap) {
            recordDot(size: scale.recordSize)
                .opacity(IslandSlots.opacity(for: max(slots.dot, slots.clock)))
            Text(TimeFormat.clock(elapsed))
                .font(Ink.mono(scale.clockFontSize))
                .monospacedDigit()
                .foregroundStyle(Ink.secondary)
                .lineLimit(1)
                .frame(width: scale.clockSpan, alignment: .leading)
                .opacity(IslandSlots.opacity(for: slots.clock))
        }
        .frame(width: layout.leadingSide, alignment: .center)
        .frame(minHeight: scale.chipMinHeight)
        .clipped()
        .accessibilityHidden(max(slots.dot, slots.clock) < 0.05)
    }

    private func trailing(_ layout: IslandLayout) -> some View {
        let scale = layout.scale
        let chipOpen = slots.chip
        let percentOpen = slots.percent
        return ZStack {
            CaptureCountChip(
                count: max(captures, 1),
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

    @ViewBuilder
    private func recordDot(size: CGFloat) -> some View {
        let square = Rectangle()
            .fill(Ink.record)
            .frame(width: size, height: size)
        if pulses {
            square
                .opacity(pulse ? 1 : 0.35)
                .animation(.easeInOut(duration: 0.85).repeatForever(autoreverses: true), value: pulse)
        } else {
            square
        }
    }
}

/// A frozen recording island for onboarding: 0:12 on the clock, a mid-sentence
/// comb, and two captures. Same face, metrics and bevel as the live one.
struct RecordingIslandDemo: View {
    var style: IslandStyle = .classic
    var captures: Int = 2
    var elapsed: TimeInterval = 12

    var body: some View {
        RecordingIslandFace(
            style: style,
            slots: IslandSlots.recording(style: style, captures: captures),
            captures: captures,
            elapsed: elapsed,
            pulses: false
        ) { width, height in
            WaveformBars(
                levels: Self.levels(count: WaveformSamples.count),
                slotWidth: width,
                slotHeight: height,
                ink: Ink.label
            )
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Recording island, 0:12, \(captures) captures")
    }

    /// Deterministic speech-like envelope: a few syllable bumps, quiet edges.
    static func levels(count: Int) -> [CGFloat] {
        guard count > 0 else { return [] }
        return (0..<count).map { index in
            let t = Double(index) / Double(max(count - 1, 1))
            let envelope = sin(Double.pi * t)
            let syllables = 0.55 + 0.45 * abs(sin(t * 19.0 + 0.6)) * (0.7 + 0.3 * cos(t * 7.0))
            return CGFloat(max(0.06, min(1, envelope * syllables * 0.95)))
        }
    }
}
