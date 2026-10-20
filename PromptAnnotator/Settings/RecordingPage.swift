import AppKit
import SwiftUI

struct RecordingPage: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var session: SessionController
    @State private var capturing = false
    @State private var message: String?

    var body: some View {
        SettingsPageStack(title: "Recording") {
            Text("Recording window")
                .font(.system(size: 13, weight: .semibold))
            styleRow

            Text("Keyboard shortcut")
                .font(.system(size: 13, weight: .semibold))
            SettingsCard {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Toggle session")
                                .font(.system(size: 13, weight: .semibold))
                            Text("Starts and stops a recording. A tap, not a hold.")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 8)
                        Button(capturing ? "Press shortcut" : settings.chord.display) {
                            capturing = true
                            message = nil
                        }
                        .buttonStyle(.bordered)
                    }
                    if let message {
                        Text(message)
                            .font(.system(size: 12))
                            .foregroundStyle(.red)
                    } else {
                        Text("Option-Space, Command-Space, and Option-Command-Space are left alone. Shift stays free for drawing.")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(12)
            }
            .background(ShortcutCapture(active: $capturing) { event in
                apply(event)
            })

            Text("Defaults")
                .font(.system(size: 13, weight: .semibold))
            SettingsCard {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Drag captures the screen in front of you, including a window or a modal. These tools show while you hold Shift.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    Text("Tool")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    HStack(spacing: 6) {
                        ForEach(AnnotationTool.allCases, id: \.self) { tool in
                            toolButton(tool)
                        }
                    }
                    Text("Color")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .padding(.top, 4)
                    HStack(spacing: 8) {
                        ForEach(InkColor.palette, id: \.self) { color in
                            colorButton(color)
                        }
                    }
                }
                .padding(12)
            }
        }
    }

    private var styleRow: some View {
        HStack(spacing: 10) {
            ForEach(IslandStyle.allCases) { style in
                Button {
                    settings.setIslandStyle(style)
                    session.refreshChrome()
                } label: {
                    VStack(spacing: 8) {
                        styleGlyph(style)
                            .frame(height: 28)
                        Text(style.title)
                            .font(.system(size: 12, weight: .medium))
                        Text(style.detail)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .frame(height: 28)
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity)
                    .background(
                        Color(nsColor: .controlBackgroundColor),
                        in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(
                                settings.islandStyle == style ? Color.primary : Color(nsColor: .separatorColor).opacity(0.7),
                                lineWidth: settings.islandStyle == style ? 2 : 1
                            )
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder
    private func styleGlyph(_ style: IslandStyle) -> some View {
        switch style {
        case .classic:
            HStack(spacing: 4) {
                Circle().fill(Color.red).frame(width: 6, height: 6)
                Capsule().frame(width: 28, height: 4)
                WaveformBars(levels: [0.3, 0.7, 0.45, 0.9, 0.4])
            }
        case .mini:
            HStack(spacing: 4) {
                Capsule().frame(width: 22, height: 4)
                WaveformBars(levels: [0.4, 0.8, 0.5, 0.7, 0.35])
            }
        case .hidden:
            Image(systemName: "eye.slash")
                .font(.system(size: 16, weight: .medium))
        }
    }

    private func toolButton(_ tool: AnnotationTool) -> some View {
        let selected = settings.defaultTool == tool
        return Button {
            session.select(tool: tool)
        } label: {
            Image(systemName: tool.symbolName)
                .font(.system(size: 14, weight: .medium))
                .frame(width: 32, height: 28)
                .foregroundStyle(selected ? Color.primary : Color.secondary)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(selected ? Color.primary.opacity(0.1) : Color.clear)
                )
        }
        .buttonStyle(.plain)
        .help(tool.title)
    }

    private func colorButton(_ color: InkColor) -> some View {
        let selected = settings.defaultColorName == color.name
        return Button {
            session.select(color: color)
        } label: {
            Circle()
                .fill(Color(red: color.swiftUIRed, green: color.swiftUIGreen, blue: color.swiftUIBlue))
                .frame(width: 16, height: 16)
                .overlay(Circle().strokeBorder(Color.primary.opacity(selected ? 0.9 : 0.25), lineWidth: selected ? 2 : 1))
                .padding(2)
        }
        .buttonStyle(.plain)
        .help(color.name)
    }

    private func apply(_ event: NSEvent) {
        capturing = false
        if event.keyCode == 53, event.modifierFlags.intersection(.deviceIndependentFlagsMask).isEmpty {
            message = nil
            return
        }
        let chord = HotkeyChord(event: event)
        if let rejection = chord.rejection {
            message = rejection
            return
        }
        if settings.setChord(chord) {
            message = nil
        } else {
            message = "macOS would not register that shortcut."
        }
    }
}

private struct ShortcutCapture: NSViewRepresentable {
    @Binding var active: Bool
    var onKey: (NSEvent) -> Void

    func makeNSView(context: Context) -> CaptureView {
        let view = CaptureView()
        view.onKey = onKey
        return view
    }

    func updateNSView(_ nsView: CaptureView, context: Context) {
        nsView.onKey = onKey
        nsView.setCapture(active)
    }

    final class CaptureView: NSView {
        var onKey: ((NSEvent) -> Void)?
        private var capture = false
        private var monitor: Any?

        func setCapture(_ active: Bool) {
            capture = active
            sync()
        }

        private func sync() {
            if capture, monitor == nil {
                window?.makeFirstResponder(self)
                monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                    guard let self, self.capture else { return event }
                    self.onKey?(event)
                    return nil
                }
            } else if !capture, let monitor {
                NSEvent.removeMonitor(monitor)
                self.monitor = nil
            }
        }

        deinit {
            if let monitor {
                NSEvent.removeMonitor(monitor)
            }
        }
    }
}
