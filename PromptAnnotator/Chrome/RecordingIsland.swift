import SwiftUI

struct RecordingIslandView: View {
    @ObservedObject var session: SessionController
    @ObservedObject private var settings = AppSettings.shared
    @State private var pulse = false

    private var showsChrome: Bool {
        !(session.phase == .recording && settings.islandStyle == .hidden)
    }

    /// Recording and transcribing share one layout, so the capsule can ease between them.
    /// Download progress is left out: it ticks often and would restart the spring.
    private var layoutToken: String {
        let mode: String
        switch session.phase {
        case .recording:
            mode = "recording"
        case .idle:
            mode = "idle"
        case .finishing, .downloading, .preparingModel, .transcribing:
            mode = "processing"
        }
        return "\(mode)|\(settings.islandStyle.rawValue)|\(session.captureCount)|\(showsPercent ? 1 : 0)"
    }

    var body: some View {
        Group {
            if session.phase == .recording || session.isBusy {
                island
            }
        }
        .foregroundStyle(.primary)
        .padding(.horizontal, showsChrome ? 16 : 0)
        .frame(height: barHeight)
        .fixedSize(horizontal: showsChrome, vertical: false)
        .animation(.spring(response: 0.48, dampingFraction: 0.92), value: layoutToken)
        .background {
            if showsChrome {
                Capsule(style: .continuous)
                    .fill(.regularMaterial)
                    .overlay(
                        Capsule(style: .continuous)
                            .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 1)
                    )
            }
        }
    }

    private var island: some View {
        HStack(spacing: barSpacing) {
            if showsCompactDot {
                recordDot
                    .transition(.opacity)
            }
            if showsRecordLabel {
                recordLabel
                    .transition(.opacity)
            }
            if showsWaveform {
                LiveWaveform(
                    display: session.waveform,
                    slotWidth: waveformWidth,
                    slotHeight: waveformHeight
                )
            }
            if showsClock {
                timer
                    .transition(.opacity)
            }
            if showsChip {
                CaptureCountChip(count: session.captureCount)
                    .transition(.opacity)
            }
            if showsPercent, case .downloading(let fraction) = session.phase {
                Text("\(Int((fraction * 100).rounded()))%")
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 36, alignment: .leading)
                    .transition(.opacity)
            }
        }
    }

    private var showsSideChrome: Bool {
        session.phase == .recording && settings.islandStyle != .minimal && settings.islandStyle != .hidden
    }

    private var showsRecordLabel: Bool {
        session.phase == .recording && settings.islandStyle == .classic
    }

    private var showsCompactDot: Bool {
        session.phase == .recording && settings.islandStyle == .compact
    }

    private var showsClock: Bool {
        showsSideChrome
    }

    private var showsWaveform: Bool {
        if session.phase == .recording {
            return settings.islandStyle != .hidden
        }
        return session.isBusy
    }

    private var showsChip: Bool {
        guard session.captureCount > 0 else { return false }
        if session.phase == .recording {
            return showsSideChrome
        }
        return session.isBusy
    }

    private var showsPercent: Bool {
        if case .downloading(let fraction) = session.phase, fraction >= 0.01 {
            return true
        }
        return false
    }

    private var barSpacing: CGFloat {
        session.phase == .recording && settings.islandStyle == .classic ? 14 : 12
    }

    private var waveformWidth: CGFloat {
        switch settings.islandStyle {
        case .classic:
            return 210
        case .compact:
            return 156
        case .minimal, .hidden:
            return session.phase == .recording ? 196 : 210
        }
    }

    private var waveformHeight: CGFloat {
        guard session.phase == .recording else { return 26 }
        switch settings.islandStyle {
        case .classic:
            return 26
        case .compact:
            return 20
        case .minimal:
            return 22
        case .hidden:
            return 26
        }
    }

    private var recordLabel: some View {
        HStack(spacing: 8) {
            recordDot
            Text("Recording")
                .font(.system(size: 13, weight: .semibold))
        }
        .fixedSize()
    }

    private var barHeight: CGFloat {
        switch session.phase {
        case .idle:
            return 0
        case .recording:
            guard showsChrome else { return 0 }
            switch settings.islandStyle {
            case .classic:
                return 46
            case .compact, .minimal:
                return 40
            case .hidden:
                return 0
            }
        case .finishing, .downloading, .preparingModel, .transcribing:
            return 46
        }
    }

    private var timer: some View {
        Text(TimeFormat.clock(session.elapsed))
            .font(.system(size: 13, weight: .medium, design: .monospaced))
            .foregroundStyle(.secondary)
            .frame(minWidth: 44, alignment: .trailing)
    }

    private var recordDot: some View {
        Circle()
            .fill(Color.red)
            .frame(width: 8, height: 8)
            .opacity(pulse ? 1 : 0.35)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.85).repeatForever(autoreverses: true)) {
                    pulse = true
                }
            }
    }
}
