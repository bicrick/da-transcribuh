import SwiftUI

struct RecordingIslandView: View {
    @ObservedObject var session: SessionController
    @ObservedObject private var settings = AppSettings.shared
    @State private var pulse = false

    private var showsChrome: Bool {
        !(session.phase == .recording && settings.islandStyle == .hidden)
    }

    var body: some View {
        Group {
            if session.phase == .recording {
                recordingBody
            } else {
                HStack(spacing: 10) {
                    ProgressView()
                        .controlSize(.small)
                    Text(session.statusText)
                        .font(.system(size: 13, weight: .semibold))
                }
            }
        }
        .foregroundStyle(.primary)
        .padding(.horizontal, showsChrome ? 16 : 0)
        .frame(height: barHeight)
        .fixedSize(horizontal: showsChrome, vertical: false)
        .animation(.spring(response: 0.42, dampingFraction: 0.86), value: session.captureCount)
        .animation(.spring(response: 0.42, dampingFraction: 0.86), value: settings.islandStyle)
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

    @ViewBuilder
    private var recordingBody: some View {
        switch settings.islandStyle {
        case .classic:
            HStack(spacing: 14) {
                recordLabel
                WaveformBars(levels: session.levels)
                trailingClock
            }
        case .compact:
            HStack(spacing: 12) {
                recordDot
                WaveformBars(levels: session.levels, slotWidth: 132, slotHeight: 20)
                trailingClock
            }
        case .minimal:
            WaveformBars(levels: session.levels, slotWidth: 168, slotHeight: 22)
        case .hidden:
            EmptyView()
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

    private var trailingClock: some View {
        HStack(spacing: 10) {
            timer
            if session.captureCount > 0 {
                CaptureCountChip(count: session.captureCount)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .fixedSize()
    }

    private var barHeight: CGFloat {
        guard showsChrome else { return 0 }
        guard session.phase == .recording else { return 36 }
        switch settings.islandStyle {
        case .classic:
            return 46
        case .compact, .minimal:
            return 40
        case .hidden:
            return 0
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
