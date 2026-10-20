import SwiftUI

struct RecordingIslandView: View {
    @ObservedObject var session: SessionController
    @ObservedObject private var settings = AppSettings.shared
    @State private var pulse = false
    @State private var inputTitle = "Default"

    private let cardInk = Color(nsColor: NSColor(srgbRed: 0.11, green: 0.11, blue: 0.12, alpha: 1))
    private let cardMuted = Color(nsColor: NSColor(srgbRed: 0.34, green: 0.34, blue: 0.36, alpha: 1))

    private var showsChrome: Bool {
        !(session.phase == .recording && settings.islandStyle == .hidden)
    }

    var body: some View {
        Group {
            if session.phase == .recording {
                recordingBody
            } else if session.isBusy {
                processingBody
            }
        }
        .foregroundStyle(cardInk)
        .padding(.horizontal, showsChrome ? horizontalPad : 0)
        .padding(.top, showsChrome ? topPad : 0)
        .padding(.bottom, showsChrome ? bottomPad : 0)
        .fixedSize(horizontal: showsChrome, vertical: false)
        .animation(.spring(response: 0.42, dampingFraction: 0.86), value: session.captureCount)
        .animation(.spring(response: 0.42, dampingFraction: 0.86), value: settings.islandStyle)
        .background {
            if showsChrome {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(Color(nsColor: NSColor(srgbRed: 0.88, green: 0.88, blue: 0.89, alpha: 0.97)))
                    .overlay(
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .strokeBorder(Color.black.opacity(0.08), lineWidth: 1)
                    )
            }
        }
        .onAppear(perform: refreshInputTitle)
        .onChange(of: settings.inputDeviceUID) { _, _ in
            refreshInputTitle()
        }
    }

    @ViewBuilder
    private var recordingBody: some View {
        switch settings.islandStyle {
        case .classic:
            VStack(spacing: 12) {
                WaveformBars(levels: session.levels, slotWidth: traceWidth, slotHeight: 78, ink: cardInk)
                controlRow
                    .frame(width: traceWidth)
            }
        case .compact:
            HStack(spacing: 12) {
                recordDot
                WaveformBars(levels: session.levels, slotWidth: 240, slotHeight: 36, ink: cardInk)
                trailingClock
            }
        case .minimal:
            WaveformBars(levels: session.levels, slotWidth: 300, slotHeight: 44, ink: cardInk)
        case .hidden:
            EmptyView()
        }
    }

    private var processingBody: some View {
        HStack(spacing: 12) {
            WaveformBars(
                levels: session.levels,
                slotWidth: processingWidth,
                slotHeight: 48,
                ink: cardInk
            )
            if case .downloading(let fraction) = session.phase, fraction >= 0.01 {
                Text("\(Int((fraction * 100).rounded()))%")
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundStyle(cardMuted)
            }
            if session.captureCount > 0 {
                CaptureCountChip(count: session.captureCount, ink: cardInk)
            }
        }
    }

    private var traceWidth: CGFloat { 440 }

    private var processingWidth: CGFloat {
        switch settings.islandStyle {
        case .classic, .hidden:
            return traceWidth
        case .compact:
            return 240
        case .minimal:
            return 300
        }
    }

    private var controlRow: some View {
        HStack(spacing: 8) {
            Image(systemName: "mic")
                .font(.system(size: 13, weight: .medium))
            Text(inputTitle)
                .font(.system(size: 13, weight: .medium))
                .lineLimit(1)
                .frame(maxWidth: 120, alignment: .leading)
            Spacer(minLength: 8)
            if session.captureCount > 0 {
                CaptureCountChip(count: session.captureCount, ink: cardInk)
            }
            Button {
                session.toggle()
            } label: {
                Text("Stop")
                    .font(.system(size: 13, weight: .semibold))
            }
            .buttonStyle(.plain)
            .help("Stop and keep this session")
            keycaps(settings.chord.keycaps)
            Button {
                session.cancel()
            } label: {
                Text("Cancel")
                    .font(.system(size: 13, weight: .medium))
            }
            .buttonStyle(.plain)
            .help("Drop this session")
            if let cancel = settings.cancelChord {
                keycaps(cancel.keycaps)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(Color.white.opacity(0.72), in: Capsule(style: .continuous))
    }

    private func keycaps(_ titles: [String]) -> some View {
        HStack(spacing: 4) {
            ForEach(Array(titles.enumerated()), id: \.offset) { _, title in
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
                    .padding(.horizontal, title.count > 1 ? 6 : 5)
                    .padding(.vertical, 2)
                    .background(
                        Color.black.opacity(0.06),
                        in: RoundedRectangle(cornerRadius: 5, style: .continuous)
                    )
            }
        }
    }

    private var trailingClock: some View {
        HStack(spacing: 10) {
            timer
            if session.captureCount > 0 {
                CaptureCountChip(count: session.captureCount, ink: cardInk)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .fixedSize()
    }

    private var horizontalPad: CGFloat { 16 }

    private var topPad: CGFloat {
        session.phase == .recording && settings.islandStyle == .classic ? 16 : 10
    }

    private var bottomPad: CGFloat {
        session.phase == .recording && settings.islandStyle == .classic ? 12 : 10
    }

    private var timer: some View {
        Text(TimeFormat.clock(session.elapsed))
            .font(.system(size: 13, weight: .medium, design: .monospaced))
            .foregroundStyle(cardMuted)
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

    private func refreshInputTitle() {
        let uid = settings.inputDeviceUID
        guard !uid.isEmpty else {
            inputTitle = "Default"
            return
        }
        inputTitle = AudioInputs.devices().first { $0.id == uid }?.name ?? "Default"
    }
}
