import AppKit
import SwiftUI

struct ConfigurationPage: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject private var session = SessionController.shared
    @State private var capture: CaptureTarget?
    @State private var message: String?
    @State private var updateMessage = "This build is \(AppVersion.label)."
    @State private var checkingUpdate = false
    @State private var folderNote: String?
    @State private var folderPath = SessionStore.displayPath()
    @State private var customFolder = SessionStore.usesCustomFolder()
    @State private var calibratingQuietRoom = false
    @State private var quietRoomNote: String?

    private enum CaptureTarget {
        case toggle
        case cancel
    }

    var body: some View {
        SettingsPageStack(title: "Configuration") {
            Text("Keyboard shortcuts")
                .font(.system(size: 13, weight: .semibold))
            shortcutCard

            Text("Application")
                .font(.system(size: 13, weight: .semibold))
            applicationCard

            Text("Advanced")
                .font(.system(size: 13, weight: .semibold))
            advancedCard

            Text("Mutter \(AppVersion.label) is free and open source.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            HStack {
                Button("View on GitHub") {
                    NSWorkspace.shared.open(ReleaseCheck.repo)
                }
                Button("Show welcome") {
                    OnboardingPresenter.shared.show()
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
                            .font(.system(size: 13, weight: .semibold))
                        Text("Hold the recording shortcut. The menu bar command stays a tap.")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                }
                .toggleStyle(.switch)
                .padding(12)
                if let message {
                    Text(message)
                        .font(.system(size: 12))
                        .foregroundStyle(.red)
                        .padding(.horizontal, 12)
                        .padding(.bottom, 4)
                }
                Text("The menu bar repeats this shortcut under Start Session. Shift stays free for drawing. Option-Space, Command-Space, and Option-Command-Space stay with the system. Press Escape while capturing Cancel to clear it.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
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
                toggleRow("Launch at login", "Opens Mutter when you sign in.") {
                    settings.launchAtLogin
                } set: {
                    settings.setLaunchAtLogin($0)
                }
                if let note = settings.loginItemNote {
                    Text(note)
                        .font(.system(size: 12))
                        .foregroundStyle(.red)
                        .padding(.horizontal, 12)
                        .padding(.bottom, 8)
                }
                SettingsDivider()
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Updates")
                            .font(.system(size: 13, weight: .semibold))
                        Text(updateMessage)
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
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
                toggleRow("Show in the Dock", "Turn this off to keep Mutter in the menu bar only.") {
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
                quietRoomRow
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
                VStack(alignment: .leading, spacing: 6) {
                    Text("Sessions folder")
                        .font(.system(size: 13, weight: .semibold))
                    Text(folderPath)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                    if let folderNote {
                        Text(folderNote)
                            .font(.system(size: 12))
                            .foregroundStyle(.red)
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
                Text("One English model ships with the app. There is no separate experimental model list.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(12)
        }
    }

    private var quietRoomRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            settingCopy(
                "Quiet-room calibration",
                "Sit silently for about two seconds. Mutter samples the mic floor and tunes speech detection and silence-stop. Leave unset to keep the default."
            )
            HStack(spacing: 8) {
                Button(calibratingQuietRoom ? "Listening…" : "Calibrate quiet room") {
                    Task { await runQuietRoomCalibration() }
                }
                .disabled(
                    calibratingQuietRoom
                        || session.isBusy
                        || session.isStartingSession
                        || session.phase == .recording
                )
                if settings.hasSpeechGateCalibration {
                    Button("Reset") {
                        settings.setSpeechGateThreshold(nil)
                        quietRoomNote = "Using the default speech floor again."
                    }
                }
            }
            if let quietRoomNote {
                Text(quietRoomNote)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            } else if let value = settings.speechGateThreshold {
                Text(String(format: "Calibrated floor %.2f (default %.2f).", value, Double(SpeechGate.defaultThreshold)))
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
        }
    }

    @MainActor
    private func runQuietRoomCalibration() async {
        calibratingQuietRoom = true
        quietRoomNote = "Stay quiet…"
        let outcome = await QuietRoomCalibration.sampleAmbient()
        calibratingQuietRoom = false
        switch outcome {
        case .calibrated(let threshold, let ambient):
            settings.setSpeechGateThreshold(Double(threshold))
            quietRoomNote = String(
                format: "Room ~%.2f → gate %.2f. Soft speech should still clear it.",
                Double(ambient),
                Double(threshold)
            )
        case .failed(let message):
            quietRoomNote = message
        }
    }

    private func shortcutRow(title: String, detail: String, label: String, action: @escaping () -> Void) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                Text(detail)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Button(label, action: action)
                .buttonStyle(.bordered)
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
                .font(.system(size: 13, weight: .semibold))
            Text(detail)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
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
