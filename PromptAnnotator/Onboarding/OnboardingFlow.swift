import AppKit
import SwiftUI

enum OnboardingStep: Int, CaseIterable {
    case welcome
    case permissions
    case shortcut
    case model
    case practice
    case ready

    var title: String {
        switch self {
        case .welcome: return "Welcome"
        case .permissions: return "Permissions"
        case .shortcut: return "Shortcut"
        case .model: return "Model"
        case .practice: return "Try a session"
        case .ready: return "Ready"
        }
    }
}

enum OnboardingMetrics {
    static let width: CGFloat = 560
    static let height: CGFloat = 700
}

struct OnboardingFlow: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject private var session = SessionController.shared
    @StateObject private var permissions = PermissionModel()
    @State private var step: OnboardingStep = .welcome
    @State private var listening = false
    @State private var shortcutNote: String?
    @StateObject private var transfer = ModelTransfer()
    @State private var practiceTask: Task<Void, Never>?
    @State private var practiceRunning = false
    @State private var practiceOutcome: String?
    var onFinish: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 14) {
                AppLogo(side: 56)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Mutter")
                        .font(.system(size: 20, weight: .semibold))
                    Text(AppVersion.label)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }
            Text(step.title)
                .font(.system(size: 15, weight: .semibold))
            ScrollView {
                stepBody
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack {
                Text("\(step.rawValue + 1) of \(OnboardingStep.allCases.count)")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                Spacer()
                if step != .welcome {
                    Button("Back") { retreat() }
                        .disabled(practiceRunning || transfer.isWorking)
                }
                if step != .ready {
                    Button("Skip setup") { finishSetup() }
                        .disabled(practiceRunning || transfer.isWorking)
                }
                Button(primaryTitle) {
                    primaryAction()
                }
                .disabled(primaryDisabled)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(28)
        .frame(width: OnboardingMetrics.width, height: OnboardingMetrics.height)
        .background(ShortcutCapture(active: $listening) { event in
            applyShortcut(event)
        })
        .onAppear { permissions.refresh() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            permissions.refresh()
        }
        .onDisappear {
            cancelPractice()
        }
    }

    private var primaryDisabled: Bool {
        if transfer.isWorking && step == .model { return true }
        if practiceRunning { return true }
        return false
    }

    @ViewBuilder
    private var stepBody: some View {
        switch step {
        case .welcome:
            Text("Talk, and capture the screen when you want the picture with the words. This beta is free and open source.")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        case .permissions:
            permissionList
        case .shortcut:
            shortcutBody
        case .model:
            modelBody
        case .practice:
            practiceBody
        case .ready:
            Text("The menu bar icon opens Mutter again. \(settings.chord.display) starts a session and stops it. While Mutter is saving or transcribing, the icon changes so you can see it working.")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var permissionList: some View {
        VStack(alignment: .leading, spacing: 12) {
            permissionRow(
                title: "Microphone",
                detail: "Hears your voice for the transcript.",
                on: permissions.status.microphone,
                recovery: Permissions.microphoneNeedsSettings()
                    ? "Denied — use Turn On, enable Mutter, then Reopen."
                    : nil
            )
            permissionRow(
                title: "Screen Recording",
                detail: "Captures the tiles you drag while talking.",
                on: permissions.status.screen,
                recovery: permissions.status.screen
                    ? nil
                    : "If the switch is already on, turn it off and on, then Reopen."
            )
            permissionRow(
                title: "Accessibility",
                detail: "Watches the shortcut and Shift for drawing.",
                on: permissions.status.accessibility,
                recovery: permissions.status.accessibility
                    ? nil
                    : "Mutter must appear in the list. Turn On prompts for that, then Reopen."
            )
            Text("After you change a switch in System Settings, Reopen so Mutter picks it up.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Button("Turn On") {
                    Task {
                        _ = await Permissions.requestMicrophone()
                        Permissions.revealSettings(for: Permissions.current())
                        permissions.refresh()
                    }
                }
                Button("Reopen") {
                    Permissions.relaunch()
                }
            }
            if permissions.status.isReady {
                Text("All three are on. Continue.")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func permissionRow(title: String, detail: String, on: Bool, recovery: String?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Image(systemName: on ? "checkmark.circle" : "circle")
                    .foregroundStyle(.primary)
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                Spacer()
                Text(on ? "On" : "Off")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            Text(detail)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if let recovery, !on {
                Text(recovery)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var shortcutBody: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("A tap starts. A second tap stops. The menu bar repeats this chord so you can find it later. Shift stays free, because Shift is how you draw.")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                ShortcutBadge(text: listening ? "Press shortcut" : settings.chord.display)
                Button(listening ? "Listening" : "Change") {
                    listening = true
                    shortcutNote = nil
                }
                .disabled(listening)
                Button("Use ⌃⌥Space") {
                    listening = false
                    shortcutNote = settings.setChord(.default) ? nil : "macOS would not register that shortcut."
                }
            }
            Text("Hold the chord instead of tapping if you turn on push-to-talk later in Configuration.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if let shortcutNote {
                Text(shortcutNote)
                    .font(.system(size: 12))
                    .foregroundStyle(.red)
            }
        }
    }

    private var modelBody: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Download an English model before the first session. Balanced is the one this app is built around. The first download can take a minute on a slow network.")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            SpeechModelPicker(settings: settings, transfer: transfer, showsDownloadButton: false)
            if transfer.isWorking, let fraction = transfer.fraction {
                ProgressView(value: min(1, max(0, fraction)))
                    .progressViewStyle(.linear)
                Text("Downloading \(Int((fraction * 100).rounded()))%. Keep this window open.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            } else if modelIsReady {
                Text("Selected model is on this Mac. Continue when you are ready.")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
            } else {
                Text("Press Download to fetch the selected model, then Continue.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var practiceBody: some View {
        VStack(alignment: .leading, spacing: 10) {
            guideRow("1", "Talk for a few seconds, or stay quiet — both paths are fine.")
            guideRow("2", "Drag a rectangle to capture the front window when you want a tile.")
            guideRow("3", "Hold Shift to annotate. Release Shift to save that tile.")
            Text("Try a short take now. Mutter stops after about five seconds and shows what happened.")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if !permissions.status.isReady {
                Text("Permissions are still off. Go Back and turn them on, then Reopen if needed.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            } else if !modelIsReady {
                Text("The speech model is not on disk yet. Go Back and download it.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            HStack {
                Button(practiceRunning ? practiceLiveTitle : "Try a 5-second session") {
                    startPractice()
                }
                .disabled(practiceRunning || session.isBusy || !practiceAllowed)
                if practiceRunning {
                    Button("Cancel") {
                        cancelPractice()
                    }
                }
            }
            if let practiceOutcome {
                Text(practiceOutcome)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else if practiceRunning, let live = session.menuStatusLine, !live.isEmpty {
                Text(live)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            Text("You can skip this and try later from Home or the menu bar.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
    }

    private var practiceAllowed: Bool {
        permissions.status.isReady && modelIsReady
    }

    private var practiceLiveTitle: String {
        if session.phase == .recording {
            return "Listening…"
        }
        if session.isBusy {
            return session.statusText.isEmpty ? "Working…" : session.statusText
        }
        return "Working…"
    }

    private var modelIsReady: Bool {
        WhisperKitTranscriber.modelIsInstalled()
    }

    private var primaryTitle: String {
        if step == .model, !modelIsReady {
            if transfer.isWorking, let fraction = transfer.fraction {
                return "Downloading \(Int((fraction * 100).rounded()))%"
            }
            return "Download"
        }
        return step == .ready ? "Open Mutter" : "Continue"
    }

    private func primaryAction() {
        if step == .model, !modelIsReady {
            transfer.download(settings.speechModel)
            return
        }
        advance()
    }

    private func guideRow(_ number: String, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(number)
                .font(.system(size: 12, weight: .semibold))
                .frame(width: 16, alignment: .leading)
            Text(text)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func advance() {
        listening = false
        guard let next = OnboardingStep(rawValue: step.rawValue + 1) else {
            finishSetup()
            return
        }
        if next == .permissions {
            enterPermissions()
        }
        if next == .practice {
            practiceOutcome = nil
            permissions.refresh()
        }
        step = next
    }

    private func enterPermissions() {
        Task {
            _ = await Permissions.requestMicrophone()
            permissions.refresh()
        }
        _ = Permissions.requestScreenRecording()
        _ = Permissions.requestAccessibilityPrompt()
        permissions.refresh()
    }

    private func retreat() {
        listening = false
        cancelPractice()
        if let previous = OnboardingStep(rawValue: step.rawValue - 1) {
            step = previous
        }
    }

    private func finishSetup() {
        cancelPractice()
        onFinish()
    }

    private func startPractice() {
        guard practiceAllowed, !practiceRunning, !session.isBusy else { return }
        practiceOutcome = nil
        practiceRunning = true
        practiceTask?.cancel()
        practiceTask = Task { @MainActor in
            let started = await session.startOnboardingPractice()
            if Task.isCancelled {
                if session.phase == .recording { session.cancel() }
                practiceRunning = false
                return
            }
            guard started else {
                practiceRunning = false
                practiceOutcome = session.lastError
                    ?? "Couldn't start. Check permissions, then try again."
                return
            }
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            if Task.isCancelled {
                if session.phase == .recording { session.cancel() }
                practiceRunning = false
                return
            }
            if session.phase == .recording {
                session.toggle()
            }
            while session.phase == .recording || session.isBusy {
                if Task.isCancelled {
                    if session.phase == .recording { session.cancel() }
                    practiceRunning = false
                    return
                }
                try? await Task.sleep(nanoseconds: 200_000_000)
            }
            guard !Task.isCancelled else {
                practiceRunning = false
                return
            }
            practiceRunning = false
            practiceOutcome = cannedPracticeSuccess()
        }
    }

    private func cannedPracticeSuccess() -> String {
        let quiet = session.lastError == "No speech detected"
        if let error = session.lastError, !quiet {
            return error
        }
        if quiet {
            return "That worked. Quiet rooms show “No speech detected” in the menu — intentional, not broken. Say a sentence next time; the words go to the clipboard."
        }
        return "That worked. Your words are on the clipboard. \(settings.chord.display) starts and stops anytime from the menu bar."
    }

    private func cancelPractice() {
        practiceTask?.cancel()
        practiceTask = nil
        if practiceRunning {
            if session.phase == .recording {
                session.cancel()
            }
            practiceRunning = false
        }
    }

    private func applyShortcut(_ event: NSEvent) {
        listening = false
        let chord = HotkeyChord(event: event)
        if let rejection = chord.rejection {
            shortcutNote = rejection
            return
        }
        shortcutNote = settings.setChord(chord) ? nil : "That shortcut is already used, or macOS would not register it."
    }
}

@MainActor
final class OnboardingPresenter {
    static let shared = OnboardingPresenter()

    private var window: NSWindow?

    func show() {
        window?.orderOut(nil)
        window = nil
        let window = ensure()
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    func close() {
        window?.orderOut(nil)
    }

    private func ensure() -> NSWindow {
        if let window { return window }
        let root = OnboardingFlow(settings: AppSettings.shared) {
            OnboardingStore.finish()
            self.close()
            SettingsPresenter.shared.show()
        }
        let host = NSHostingView(rootView: root)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: OnboardingMetrics.width, height: OnboardingMetrics.height),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Welcome to Mutter"
        window.isReleasedWhenClosed = false
        window.contentView = host
        window.center()
        self.window = window
        return window
    }
}
