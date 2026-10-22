import AppKit
import SwiftUI

struct ConfigurationPage: View {
    @ObservedObject var settings: AppSettings
    @State private var capture: CaptureTarget?
    @State private var message: String?
    @State private var updateMessage = "This build is \(AppVersion.label)."
    @State private var checkingUpdate = false
    @State private var folderNote: String?
    @State private var folderPath = SessionStore.displayPath()
    @State private var customFolder = SessionStore.usesCustomFolder()

    private enum CaptureTarget {
        case toggle
        case cancel
    }

    var body: some View {
        SettingsPageStack(
            title: "General",
            subtitle: "Shortcuts, launch behavior, and paste rules. Theme and island live on Appearance."
        ) {
            SettingsSection(title: "Keyboard shortcuts") {
                shortcutCard
            }
            SettingsSection(title: "Application") {
                applicationCard
            }
            SettingsSection(title: "Advanced") {
                advancedCard
            }
            SettingsSection(
                footer: "da transcribuh \(AppVersion.label) is free and open source."
            ) {
                HStack(spacing: Ink.space2) {
                    Button("View on GitHub") {
                        NSWorkspace.shared.open(ReleaseCheck.repo)
                    }
                    .buttonStyle(InkSecondaryButtonStyle())
                    Button("Show welcome") {
                        OnboardingPresenter.shared.show()
                    }
                    .buttonStyle(InkSecondaryButtonStyle())
                }
            }
        }
        .background(ShortcutCapture(active: Binding(
            get: { capture != nil },
            set: { if !$0 { capture = nil } }
        )) { event in
            apply(event)
        })
    }

    private var shortcutCard: some View {
        InkCard {
            VStack(alignment: .leading, spacing: 0) {
                InkSettingRow(
                    title: "Start and stop",
                    detail: settings.pushToTalk
                        ? "Hold \(settings.chord.display) to talk. Release to stop."
                        : "\(settings.chord.display) starts a session. Press it again to stop."
                ) {
                    InkShortcutRecorder(
                        keys: settings.chord.keycaps,
                        listening: capture == .toggle
                    ) {
                        capture = .toggle
                        message = nil
                    }
                }
                InkDivider(leading: 0)
                InkSettingRow(
                    title: "Cancel recording",
                    detail: settings.cancelChord.map {
                        "\($0.display) drops the session without a transcript or screenshot."
                    } ?? "Optional. Set a shortcut to drop a take without saving."
                ) {
                    InkShortcutRecorder(
                        keys: settings.cancelChord?.keycaps ?? [],
                        listening: capture == .cancel,
                        emptyLabel: "None"
                    ) {
                        capture = .cancel
                        message = nil
                    }
                }
                InkDivider(leading: 0)
                InkToggleRow(
                    title: "Push to talk",
                    detail: "Hold the recording shortcut. The menu bar command stays a tap.",
                    isOn: Binding(
                        get: { settings.pushToTalk },
                        set: { settings.setPushToTalk($0) }
                    )
                )
                if let message {
                    Text(message)
                        .font(Ink.captionFont)
                        .foregroundStyle(Ink.error)
                        .padding(.horizontal, Ink.rowHPad)
                        .padding(.bottom, Ink.space2)
                }
                Text("Click the keycaps, press a new combo (needs a modifier, or a function key). It re-registers live — no relaunch. Shift stays free for drawing. Command-Space and Option-Command-Space stay with the system. Escape while capturing Cancel clears it.")
                    .font(Ink.captionFont)
                    .foregroundStyle(Ink.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, Ink.rowHPad)
                    .padding(.bottom, Ink.space3)
                HStack {
                    Spacer()
                    Button("Reset to ⌥Space") {
                        capture = nil
                        message = settings.setChord(.default) ? nil : "macOS would not register the default shortcut."
                    }
                    .buttonStyle(InkSecondaryButtonStyle())
                }
                .padding(.horizontal, Ink.rowHPad)
                .padding(.bottom, Ink.rowVPad)
            }
        }
    }

    private var applicationCard: some View {
        InkCard {
            VStack(alignment: .leading, spacing: 0) {
                InkToggleRow(
                    title: "Launch at login",
                    detail: "Opens da transcribuh when you sign in.",
                    isOn: Binding(
                        get: { settings.launchAtLogin },
                        set: { settings.setLaunchAtLogin($0) }
                    )
                )
                if let note = settings.loginItemNote {
                    Text(note)
                        .font(Ink.captionFont)
                        .foregroundStyle(Ink.error)
                        .padding(.horizontal, Ink.rowHPad)
                        .padding(.bottom, Ink.space2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                InkDivider(leading: 0)
                InkSettingRow(title: "Updates", detail: updateMessage) {
                    Button(checkingUpdate ? "Checking" : "Check") {
                        checkForUpdate()
                    }
                    .buttonStyle(InkSecondaryButtonStyle())
                    .disabled(checkingUpdate)
                }
                InkDivider(leading: 0)
                InkToggleRow(
                    title: "Keep this window above others",
                    detail: "The settings window stays in front while you work.",
                    isOn: Binding(
                        get: { settings.keepWindowOnTop },
                        set: { settings.setKeepWindowOnTop($0) }
                    )
                )
                InkDivider(leading: 0)
                InkToggleRow(
                    title: "Show in the Dock",
                    detail: "Turn this off to keep da transcribuh in the menu bar only.",
                    isOn: Binding(
                        get: { settings.showInDock },
                        set: { settings.setShowInDock($0) }
                    )
                )
                InkDivider(leading: 0)
                InkToggleRow(
                    title: "Write errors to a log",
                    detail: "Records start failures and transcription errors.",
                    isOn: Binding(
                        get: { settings.errorLogging },
                        set: { settings.setErrorLogging($0) }
                    )
                )
                HStack {
                    Spacer()
                    Button("Show log") {
                        let url = ErrorLog.fileURL()
                        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                        if !FileManager.default.fileExists(atPath: url.path) {
                            try? Data().write(to: url)
                        }
                        NSWorkspace.shared.activateFileViewerSelecting([url])
                    }
                    .buttonStyle(InkSecondaryButtonStyle())
                }
                .padding(.horizontal, Ink.rowHPad)
                .padding(.bottom, Ink.rowVPad)
            }
        }
    }

    private var advancedCard: some View {
        InkCard {
            VStack(alignment: .leading, spacing: 0) {
                InkSettingRow(
                    title: "Stop after silence",
                    detail: "Ends a spoken session once the microphone stays quiet."
                ) {
                    InkMenuPicker(
                        title: "Stop after silence",
                        selection: Binding(
                            get: { settings.silenceStopSeconds },
                            set: { settings.setSilenceStopSeconds($0) }
                        ),
                        options: [
                            (0.0, "Off"),
                            (0.75, "0.75 s"),
                            (1.25, "1.25 s"),
                            (2.0, "2 s"),
                            (3.0, "3 s"),
                        ]
                    )
                }
                InkDivider(leading: 0)
                InkSettingRow(
                    title: "Maximum session",
                    detail: "Stops a long recording even if you are still talking."
                ) {
                    InkMenuPicker(
                        title: "Maximum session",
                        selection: Binding(
                            get: { settings.maxSessionMinutes },
                            set: { settings.setMaxSessionMinutes($0) }
                        ),
                        options: [
                            (0.0, "Off"),
                            (2.0, "2 min"),
                            (5.0, "5 min"),
                            (10.0, "10 min"),
                            (30.0, "30 min"),
                        ]
                    )
                }
                InkDivider(leading: 0)
                InkToggleRow(
                    title: "Normalize quiet speech",
                    detail: "Raises a quiet take before transcription. Silence is left alone.",
                    isOn: Binding(
                        get: { settings.normalizeSpeech },
                        set: { settings.setNormalizeSpeech($0) }
                    )
                )
                InkDivider(leading: 0)
                VStack(alignment: .leading, spacing: Ink.space2) {
                    Text("Sessions folder")
                        .font(Ink.rowTitleFont)
                        .foregroundStyle(Ink.label)
                    Text(folderPath)
                        .font(Ink.captionFont)
                        .foregroundStyle(Ink.secondary)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                    if let folderNote {
                        Text(folderNote)
                            .font(Ink.captionFont)
                            .foregroundStyle(Ink.error)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    HStack(spacing: Ink.space2) {
                        Button("Change") { chooseFolder() }
                            .buttonStyle(InkSecondaryButtonStyle())
                        Button("Use Documents") {
                            SessionStore.reset()
                            refreshFolder()
                        }
                        .buttonStyle(InkSecondaryButtonStyle())
                        .disabled(!customFolder)
                        Button("Show") {
                            if let root = try? SessionPaths.sessionsRoot() {
                                NSWorkspace.shared.open(root)
                            }
                        }
                        .buttonStyle(InkSecondaryButtonStyle())
                    }
                }
                .padding(.horizontal, Ink.rowHPad)
                .padding(.vertical, Ink.rowVPad)
                InkDivider(leading: 0)
                InkToggleRow(
                    title: "Paste when the session ends",
                    detail: "On by default. Pastes into the front app, the way a dictation stop does. It waits while this window is focused.",
                    isOn: Binding(
                        get: { settings.pasteOnStop },
                        set: { settings.setPasteOnStop($0) }
                    )
                )
                InkDivider(leading: 0)
                InkToggleRow(
                    title: "Press Return when Shift is held",
                    detail: "After an automatic paste, Shift sends the message.",
                    isOn: Binding(
                        get: { settings.returnOnShift },
                        set: { settings.setReturnOnShift($0) }
                    ),
                    enabled: settings.pasteOnStop
                )
                InkDivider(leading: 0)
                InkToggleRow(
                    title: "Capitalize the pasted transcript",
                    detail: "The first letter is capitalized. A leading tile number stays put.",
                    isOn: Binding(
                        get: { settings.capitalizeTranscript },
                        set: { settings.setCapitalizeTranscript($0) }
                    )
                )
                Text("Speech models are on the Models page.")
                    .font(Ink.captionFont)
                    .foregroundStyle(Ink.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, Ink.rowHPad)
                    .padding(.bottom, Ink.rowVPad)
            }
        }
    }

    private func apply(_ event: NSEvent) {
        let target = capture
        capture = nil
        switch target {
        case .toggle:
            message = RecordingChordCapture.message(
                for: RecordingChordCapture.applyToggleEvent(event, settings: settings)
            )
        case .cancel:
            let bareEscape = event.keyCode == 53
                && event.modifierFlags.intersection(.deviceIndependentFlagsMask).isEmpty
            if bareEscape {
                _ = settings.setCancelChord(nil)
                message = nil
                return
            }
            let chord = HotkeyChord(event: event)
            if let rejection = chord.rejection {
                message = rejection
                return
            }
            message = settings.setCancelChord(chord)
                ? nil
                : "That shortcut is already used, or macOS would not register it."
        case nil:
            break
        }
    }

    private func checkForUpdate() {
        checkingUpdate = true
        Task {
            let message = await ReleaseCheck.lookUp()
            updateMessage = message
            checkingUpdate = false
        }
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Choose"
        panel.message = "Sessions and their transcripts will be saved in this folder."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try SessionStore.choose(url)
            folderNote = nil
            refreshFolder()
        } catch {
            folderNote = error.localizedDescription
        }
    }

    private func refreshFolder() {
        folderPath = SessionStore.displayPath()
        customFolder = SessionStore.usesCustomFolder()
    }
}
