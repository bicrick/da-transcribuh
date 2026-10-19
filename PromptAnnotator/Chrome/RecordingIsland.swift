import SwiftUI

struct RecordingIslandView: View {
    @ObservedObject var session: SessionController
    @State private var pulse = false

    var body: some View {
        HStack(spacing: 10) {
            if session.phase == .recording {
                recordDot
                Text("Recording")
                    .font(.system(size: 13, weight: .semibold))
                Text(TimeFormat.clock(session.elapsed))
                    .font(.system(size: 13, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 44, alignment: .trailing)
                WaveformBars(levels: session.levels)
                if session.showsPenState {
                    hairline
                    Image(systemName: session.tool.symbolName)
                        .font(.system(size: 12, weight: .semibold))
                    Text(session.tool.title)
                        .font(.system(size: 12, weight: .medium))
                }
            } else {
                ProgressView()
                    .controlSize(.small)
                Text(session.statusText)
                    .font(.system(size: 13, weight: .semibold))
            }
        }
        .foregroundStyle(.primary)
        .padding(.horizontal, 14)
        .frame(height: 36)
        .fixedSize(horizontal: true, vertical: false)
        .background(.regularMaterial, in: Capsule(style: .continuous))
        .overlay(
            Capsule(style: .continuous)
                .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 1)
        )
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
