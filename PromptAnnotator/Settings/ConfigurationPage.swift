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
        SettingsPageStack(title: "General") {
            SettingsSection(title: "Appearance") {
                appearanceCard
            }
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
                HStack(spacing: 10) {
                    Button("View on GitHub") {
                        NSWorkspace.shared.open(ReleaseCheck.repo)
                    }
                    Button("Show welcome") {
                        OnboardingPresenter.shared.show()
                    }
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

    private var appearanceCard: some View {
        SettingsCard {
            VStack(alignment: .leading, spacing: Ink.space3) {
                VStack(alignment: .leading, spacing: Ink.titleDescGap) {
                    Text("Theme")
                        .font(Ink.rowTitleFont)
                        .foregroundStyle(Ink.label)
                    Text("System follows macOS. Light and Dark lock Settings, the menu panel, and the recording island / annotate chrome.")
                        .font(Ink.captionFont)
                        .foregroundStyle(Ink.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                InkAppearanceSegment(
                    selection: Binding(
                        get: { settings.appearance },
                        set: { settings.setAppearance($0) }
                    ),
                    onChange: { settings.setAppearance($0) }
                )
            }
            .padding(Ink.cardPad)
        }
    }

    private var shortcutCard: some View {
        SettingsCard {
            VStack(alignment: .leading, spacing: 0) {
                shortcutRow(
                    title: "Start and stop",
                    detail: settings.pushToTalk
                        ? "Hold \(settings.chord.display) to talk. Release to stop."
                        : "\(settings.chord.display) starts a session. Press it again to stop.",
                    label: capture == .toggle ? "Press shortcut" : settings.chord.display
                ) {
                    capture = .toggle
                    message = nil
                }
                SettingsDivider()
                shortcutRow(
                    title: "Cancel recording",
                    detail: settings.cancelChord.map {
                        "\($0.display) drops the session without a transcript or screenshot."
                    } ?? "Optional. Set a shortcut to drop a take without saving.",
                    label: capture == .cancel ? "Press shortcut" : (settings.cancelChord?.display ?? "None")
                ) {
                    capture = .cancel
                    message = nil
                }
                SettingsDivider()
                Toggle(isOn: Binding(
                    get: { settings.pushToTalk },
                    set: { settings.setPushToTalk($0) }
                )) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Push to talk")
                            .font(Ink.rowTitleFont)
                            .foregroundStyle(Ink.label)
                        Text("Hold the recording shortcut. The menu bar command stays a tap.")
                            .font(Ink.captionFont)
                            .foregroundStyle(Ink.secondary)
                    }
                }
                .toggleStyle(.switch)
                .padding(12)
                if let message {
                    Text(message)
                        .font(Ink.captionFont)
                        .foregroundStyle(Ink.error)
                        .padding(.horizontal, 12)
                        .padding(.bottom, 4)
                }
                Text("The menu bar repeats this shortcut under Start Session. Shift stays free for drawing. Option-Space, Command-Space, and Option-Command-Space stay with the system. Press Escape while capturing Cancel to clear it.")
                    .font(Ink.captionFont)
                    .foregroundStyle(Ink.secondary)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 8)
                HStack {
                    Spacer()
                    Button("Reset to ⌃⌥Space") {
                        capture = nil
                        message = settings.setChord(.default) ? nil : "macOS would not register the default shortcut."
                    }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 12)
            }
        }
    }

    private var applicationCard: some View {
        SettingsCard {
            VStack(alignment: .leading, spacing: 0) {
                toggleRow("Launch at login", "Opens da transcribuh when you sign in.") {
                    settings.launchAtLogin
                } set: {
                    settings.setLaunchAtLogin($0)
                }
                if let note = settings.loginItemNote {
                    Text(note)
                        .font(Ink.captionFont)
                        .foregroundStyle(Ink.error)
                        .padding(.horizontal, Ink.rowHPad)
                        .padding(.bottom, Ink.space2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                SettingsDivider()
                HStack(spacing: Ink.space3) {
                    VStack(alignment: .leading, spacing: Ink.titleDescGap) {
                        Text("Updates")
                            .font(Ink.rowTitleFont)
                            .foregroundStyle(Ink.label)
                        Text(updateMessage)
                            .font(Ink.captionFont)
                            .foregroundStyle(Ink.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 8)
                    Button(checkingUpdate ? "Checking" : "Check") {
                        checkForUpdate()
                    }
                    .disabled(checkingUpdate)
                }
                .padding(12)
                SettingsDivider()
                toggleRow("Keep this window above others", "The settings window stays in front while you work.") {
                    settings.keepWindowOnTop
                } set: {
                    settings.setKeepWindowOnTop($0)
                }
                SettingsDivider()
                toggleRow("Show in the Dock", "Turn this off to keep da transcribuh in the menu bar only.") {
                    settings.showInDock
                } set: {
                    settings.setShowInDock($0)
                }
                SettingsDivider()
                toggleRow("Write errors to a log", "Records start failures and transcription errors.") {
                    settings.errorLogging
                } set: {
                    settings.setErrorLogging($0)
                }
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
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 12)
            }
        }
    }

    private var advancedCard: some View {
        SettingsCard {
            VStack(alignment: .leading, spacing: 12) {
                labeledPicker("Stop after silence", "Ends a spoken session once the microphone stays quiet.") {
                    Picker("Stop after silence", selection: Binding(
                        get: { settings.silenceStopSeconds },
                        set: { settings.setSilenceStopSeconds($0) }
                    )) {
                        Text("Off").tag(0.0)
                        Text("0.75 s").tag(0.75)
                        Text("1.25 s").tag(1.25)
                        Text("2 s").tag(2.0)
                        Text("3 s").tag(3.0)
                    }
                    .labelsHidden()
                    .frame(width: 110)
                }
                labeledPicker("Maximum session", "Stops a long recording even if you are still talking.") {
                    Picker("Maximum session", selection: Binding(
                        get: { settings.maxSessionMinutes },
                        set: { settings.setMaxSessionMinutes($0) }
                    )) {
                        Text("Off").tag(0.0)
                        Text("2 min").tag(2.0)
                        Text("5 min").tag(5.0)
                        Text("10 min").tag(10.0)
                        Text("30 min").tag(30.0)
                    }
                    .labelsHidden()
                    .frame(width: 110)
                }
                Toggle(isOn: Binding(
                    get: { settings.normalizeSpeech },
                    set: { settings.setNormalizeSpeech($0) }
                )) {
                    settingCopy("Normalize quiet speech", "Raises a quiet take before transcription. Silence is left alone.")
                }
                .toggleStyle(.switch)
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
                    HStack {
                        Button("Change") { chooseFolder() }
                        Button("Use Documents") {
                            SessionStore.reset()
                            refreshFolder()
                        }
                            .disabled(!customFolder)
                        Button("Show") {
                            if let root = try? SessionPaths.sessionsRoot() {
                                NSWorkspace.shared.open(root)
                            }
                        }
                    }
                }
                Toggle(isOn: Binding(
                    get: { settings.pasteOnStop },
                    set: { settings.setPasteOnStop($0) }
                )) {
                    settingCopy("Paste when the session ends", "On by default. Pastes into the front app, the way a dictation stop does. It waits while this window is focused.")
                }
                .toggleStyle(.switch)
                Toggle(isOn: Binding(
                    get: { settings.returnOnShift },
                    set: { settings.setReturnOnShift($0) }
                )) {
                    settingCopy("Press Return when Shift is held", "After an automatic paste, Shift sends the message.")
                }
                .toggleStyle(.switch)
                .disabled(!settings.pasteOnStop)
                Toggle(isOn: Binding(
                    get: { settings.capitalizeTranscript },
                    set: { settings.setCapitalizeTranscript($0) }
                )) {
                    settingCopy("Capitalize the pasted transcript", "The first letter is capitalized. A leading tile number stays put.")
                }
                .toggleStyle(.switch)
                Text("Speech models are on the Models page.")
                    .font(Ink.captionFont)
                    .foregroundStyle(Ink.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(12)
        }
    }

    private func shortcutRow(title: String, detail: String, label: String, action: @escaping () -> Void) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(Ink.rowTitleFont)
                    .foregroundStyle(Ink.label)
                Text(detail)
                    .font(Ink.captionFont)
                    .foregroundStyle(Ink.secondary)
            }
            Spacer(minLength: 8)
            Button(label, action: action)
                .buttonStyle(InkSecondaryButtonStyle())
        }
        .padding(12)
    }

    private func toggleRow(_ title: String, _ detail: String, get: @escaping () -> Bool, set: @escaping (Bool) -> Void) -> some View {
        Toggle(isOn: Binding(get: get, set: set)) {
            settingCopy(title, detail)
        }
        .toggleStyle(.switch)
        .padding(12)
    }

    private func settingCopy(_ title: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(Ink.rowTitleFont)
                .foregroundStyle(Ink.label)
            Text(detail)
                .font(Ink.captionFont)
                .foregroundStyle(Ink.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func labeledPicker<Control: View>(_ title: String, _ detail: String, @ViewBuilder control: () -> Control) -> some View {
        HStack(alignment: .center, spacing: 12) {
            settingCopy(title, detail)
            Spacer(minLength: 8)
            control()
        }
    }

    private func apply(_ event: NSEvent) {
        let target = capture
        capture = nil
        let bareEscape = event.keyCode == 53 && event.modifierFlags.intersection(.deviceIndependentFlagsMask).isEmpty
        if bareEscape {
            if target == .cancel {
                _ = settings.setCancelChord(nil)
            }
            message = nil
            return
        }
        let chord = HotkeyChord(event: event)
        if let rejection = chord.rejection {
            message = rejection
            return
        }
        switch target {
        case .toggle:
            message = settings.setChord(chord) ? nil : "That shortcut is already used, or macOS would not register it."
        case .cancel:
            message = settings.setCancelChord(chord) ? nil : "That shortcut is already used, or macOS would not register it."
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
