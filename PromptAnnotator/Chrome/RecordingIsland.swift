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
                switch settings.islandStyle {
                case .classic:
                    HStack(spacing: 10) {
                        recordDot
                        Text("Recording")
                            .font(.system(size: 13, weight: .semibold))
                        timer
                        WaveformBars(levels: session.levels)
                        penState(includeTitle: true)
                    }
                case .mini:
                    HStack(spacing: 8) {
                        recordDot
                        timer
                        WaveformBars(levels: session.levels)
                        penState(includeTitle: false)
                    }
                case .hidden:
                    EmptyView()
                }
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
        .padding(.horizontal, showsChrome ? 14 : 0)
        .frame(height: showsChrome ? 36 : 0)
        .fixedSize(horizontal: showsChrome, vertical: false)
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

    private var timer: some View {
        Text(TimeFormat.clock(session.elapsed))
            .font(.system(size: 13, weight: .medium, design: .monospaced))
            .foregroundStyle(.secondary)
            .frame(minWidth: 44, alignment: .trailing)
    }

    @ViewBuilder
    private func penState(includeTitle: Bool) -> some View {
        if session.showsPenState {
            hairline
            Image(systemName: session.tool.symbolName)
                .font(.system(size: 12, weight: .semibold))
            if includeTitle {
                Text(session.tool.title)
                    .font(.system(size: 12, weight: .medium))
            }
        }
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

    private var hairline: some View {
        Rectangle()
            .fill(Color(nsColor: .separatorColor))
            .frame(width: 1, height: 16)
    }
}

struct WaveformBars: View {
    var levels: [CGFloat]

    var body: some View {
        HStack(alignment: .center, spacing: 2) {
            ForEach(Array(levels.enumerated()), id: \.offset) { _, level in
                Capsule(style: .continuous)
                    .fill(Color.secondary)
                    .frame(width: 3, height: max(4, 4 + level * 12))
            }
        }
        .frame(width: 23, height: 16)
    }
}
