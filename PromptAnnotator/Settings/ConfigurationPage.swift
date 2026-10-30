import AppKit
import SwiftUI

struct ConfigurationPage: View {
    @ObservedObject var settings: AppSettings
    @State private var capture: CaptureTarget?
    @State private var message: String?
    @ObservedObject private var updates = UpdateController.shared
    @State private var folderNote: String?
    @State private var folderPath = SessionStore.displayPath()
    @State private var customFolder = SessionStore.usesCustomFolder()

    private enum CaptureTarget {
        case toggle
        case cancel
        case clipboard
    }

    var body: some View {
        SettingsPageStack(
            title: "General",
            subtitle: "Shortcuts, launch behavior, and paste rules. Theme and island live on Appearance."
        ) {
            SettingsSection(title: "Keyboard shortcuts") {
                shortcutCard
            }
            SettingsSection(
                title: "Clipboard history",
                footer: "Full controls live on the Clipboard tab."
            ) {
                InkCard {
                    InkSettingRow(
                        title: "Clipboard tab",
                        detail: "Enable, shortcut, storage, appearance, pins, ignore, and advanced."
                    ) {
                        Text("→")
                            .font(Ink.mono(12))
                            .foregroundStyle(Ink.secondary)
                    }
                }
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
                    detail: "\(settings.chord.display) — \(settings.hotkeyBehavior.title.lowercased())."
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
                InkSettingRow(
                    title: "Activation",
                    detail: settings.hotkeyBehavior.detail
                ) {
                    InkMenuPicker(
                        title: "Activation",
                        selection: Binding(
                            get: { settings.hotkeyBehavior },
                            set: { settings.setHotkeyBehavior($0) }
                        ),
                        options: HotkeyBehavior.allCases.map { ($0, $0.title) }
                    )
                }
                InkDivider(leading: 0)
                InkSettingRow(
                    title: "Screenshot key",
                    detail: "Hold it alone for the crosshair. Drag to grab, release to cancel."
                ) {
                    InkMenuPicker(
                        title: "Screenshot key",
                        selection: Binding(
                            get: { settings.screenshotKey },
                            set: { message = settings.setScreenshotKey($0) }
                        ),
                        options: SessionModifier.screenshotChoices.map { ($0, "\($0.glyph) \($0.title)") }
                    )
                }
                InkDivider(leading: 0)
                InkSettingRow(
                    title: "Annotate key",
                    detail: "Hold it alone to draw with the default tool. Off leaves drawing on the bar."
                ) {
                    InkMenuPicker(
                        title: "Annotate key",
                        selection: Binding(
                            get: { settings.annotateKey },
                            set: { message = settings.setAnnotateKey($0) }
                        ),
                        options: SessionModifier.annotateChoices.map { (Optional($0), "\($0.glyph) \($0.title)") }
                            + [(nil, "Off")]
                    )
                }
                if let message {
                    Text(message)
                        .font(Ink.captionFont)
                        .foregroundStyle(Ink.error)
                        .padding(.horizontal, Ink.rowHPad)
                        .padding(.bottom, Ink.space2)
                }
                Text("Click the keycaps, press a new combo (modifier, function key, or use fn below). Bare fn needs Keyboard → Press 🌐 key to → Do Nothing so emoji/dictation does not steal it. Session keys stay free. ⌘Space / ⌥⌘Space stay with the system. Escape while capturing Cancel clears it.")
                    .font(Ink.captionFont)
                    .foregroundStyle(Ink.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, Ink.rowHPad)
                    .padding(.bottom, Ink.space3)
                HStack {
                    Spacer()
                    Button("Use fn") {
                        capture = nil
                        settings.setHotkeyBehavior(.holdAndDoubleTap)
                        message = settings.setChord(.default) ? nil : "Could not enable the fn shortcut."
                    }
                    .buttonStyle(InkSecondaryButtonStyle())
                    Button("Use ⌥Space") {
                        capture = nil
                        message = settings.setChord(.optionSpaceDefault) ? nil : "macOS would not register that shortcut."
                    }
                    .buttonStyle(InkSecondaryButtonStyle())
                }
                .padding(.horizontal, Ink.rowHPad)
                .padding(.bottom, Ink.rowVPad)
            }
        }
    }

    private var clipboardCard: some View {
        InkCard {
            VStack(alignment: .leading, spacing: 0) {
                InkToggleRow(
                    title: "Clipboard history",
                    detail: "On by default. \(settings.clipboardChord.display) opens the panel near the pointer.",
                    isOn: Binding(
                        get: { settings.clipboardHistoryEnabled },
                        set: { settings.setClipboardHistoryEnabled($0) }
                    )
                )
                InkDivider(leading: 0)
                InkSettingRow(
                    title: "History shortcut",
                    detail: "Paste with Enter; ⌥Enter copies only. Shares Accessibility with paste — no extra permission."
                ) {
                    InkShortcutRecorder(
                        keys: settings.clipboardChord.keycaps,
                        listening: capture == .clipboard
                    ) {
                        capture = .clipboard
                        message = nil
                    }
                }
                InkDivider(leading: 0)
                InkSettingRow(
                    title: "History size",
                    detail: "Pinned items survive Clear. More in the Clipboard tab."
                ) {
                    InkStepper(
                        title: "History size",
                        value: Binding(
                            get: { settings.clipboardHistoryLimit },
                            set: { settings.setClipboardHistoryLimit($0) }
                        ),
                        range: 20...500,
                        step: 10,
                        format: { "\($0) items" },
                        valueWidth: 84
                    )
                }
                HStack {
                    Spacer()
                    Button {
                        capture = nil
                        message = settings.setClipboardChord(.clipboardDefault)
                            ? nil
                            : "macOS would not register the default shortcut."
                    } label: {
                        InkGlyphString(text: "Reset to ⇧⌘C", size: 11)
                    }
                    .buttonStyle(InkSecondaryButtonStyle())
                    Button("Clear history") {
                        ClipboardHistoryStore.shared.clearHistory(keepingPinned: true)
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
                InkSettingRow(title: "Updates", detail: updatesDetail) {
                    Button(UpdateController.menuTitle) {
                        updates.checkForUpdates()
                    }
                    .buttonStyle(InkSecondaryButtonStyle())
                    .disabled(!updates.canCheckForUpdates)
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
                    Button("Export diagnostics…") {
                        DiagnosticsExporter.exportInteractively()
                    }
                    .buttonStyle(InkSecondaryButtonStyle())
                    .help("Zips local logs, crash reports and system info. Nothing is uploaded.")
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
                    detail: "After an automatic paste, holding Shift as the session ends sends the message.",
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
            if let rejection = chord.rejection(reserving: settings.sessionKeys) {
                message = rejection
                return
            }
            message = settings.setCancelChord(chord)
                ? nil
                : "That shortcut is already used, or macOS would not register it."
        case .clipboard:
            let bare = event.modifierFlags.intersection(.deviceIndependentFlagsMask).isEmpty
            if bare, event.keyCode == 53 { return }
            if bare, event.keyCode == 51 || event.keyCode == 117 {
                message = settings.setClipboardChord(.clipboardDefault)
                    ? nil
                    : "macOS would not register the default shortcut."
                return
            }
            let chord = HotkeyChord(event: event)
            if let rejection = chord.rejection(allowingShift: true) {
                message = rejection
                return
            }
            message = settings.setClipboardChord(chord)
                ? nil
                : "That shortcut is already used, or macOS would not register it."
        case nil:
            break
        }
    }

    private var updatesDetail: String {
        let automatic = updates.automaticallyChecksForUpdates
            ? "Checks automatically."
            : "Automatic checks are off during the beta."
        return "This build is \(AppVersion.label). \(automatic)"
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
