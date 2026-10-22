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

    var eyebrow: String {
        "Step \(rawValue + 1) of \(OnboardingStep.allCases.count)"
    }

    /// Short labels for the Paint step rail.
    static let railLabels = ["Hi", "Perm", "Keys", "Model", "Try", "Go"]

    var blurb: String? {
        switch self {
        case .welcome:
            return "Talk, and capture the screen when you want the picture with the words."
        case .permissions:
            return "Three switches. Flip them, then Reopen so da transcribuh picks them up."
        case .shortcut:
            return "A tap starts. A second tap stops. Shift stays free for drawing."
        case .model:
            return "Download an English model before the first session. Balanced is the default."
        case .practice:
            return "A short take now — or skip and try later from Home."
        case .ready:
            return "The menu bar icon opens da transcribuh again anytime."
        }
    }
}

enum OnboardingMetrics {
    static let width: CGFloat = 560
    static let height: CGFloat = 720
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
        VStack(spacing: 0) {
            onboardingChrome
            DTScrollView {
                VStack(alignment: .leading, spacing: Ink.sectionGap) {
                    InkStepRail(current: step.rawValue, labels: OnboardingStep.railLabels)
                    InkPageHeader(title: step.title, subtitle: step.blurb)
                    stepBody
                }
                .padding(.top, Ink.pageTop)
                .padding(.horizontal, Ink.pageSide)
                .padding(.bottom, Ink.pageBottom)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            footer
        }
        .frame(width: OnboardingMetrics.width, height: OnboardingMetrics.height)
        .background(Ink.window)
        .tint(Ink.label)
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

    /// Wordmark strip — same language as Settings, without SettingsPresenter traffic lights.
    private var onboardingChrome: some View {
        ZStack {
            DTWordmark(size: 13)
        }
        .frame(height: Ink.titleStripHeight)
        .frame(maxWidth: .infinity)
        .background(Ink.window)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Ink.label)
                .frame(height: 2)
        }
    }

    private var footer: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(Ink.label)
                .frame(height: 1)
            HStack(spacing: Ink.space3) {
                Text("\(step.rawValue + 1) / \(OnboardingStep.allCases.count)")
                    .font(Ink.headingFont)
                    .foregroundStyle(Ink.secondary)
                    .monospacedDigit()
                Spacer(minLength: Ink.space2)
                if step != .ready {
                    Button("Skip setup") { finishSetup() }
                        .buttonStyle(.plain)
                        .font(Ink.buttonSmallFont)
                        .foregroundStyle(Ink.secondary)
                        .disabled(practiceRunning || transfer.isWorking)
                }
                if step != .welcome {
                    Button("Back") { retreat() }
                        .buttonStyle(InkSecondaryButtonStyle())
                        .disabled(practiceRunning || transfer.isWorking)
                }
                Button(primaryTitle) {
                    primaryAction()
                }
                .buttonStyle(InkPrimaryButtonStyle(large: true, enabled: !primaryDisabled))
                .disabled(primaryDisabled)
                .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, Ink.pageSide)
            .padding(.vertical, Ink.space4)
        }
        .background(Ink.window)
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
            welcomeBody
        case .permissions:
            permissionsCard
        case .shortcut:
            shortcutCard
        case .model:
            modelCard
        case .practice:
            practiceCard
        case .ready:
            readyBody
        }
    }

    private var welcomeBody: some View {
        VStack(alignment: .leading, spacing: Ink.space5) {
            InkCard {
                InkWavePenMotif(inked: false)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Ink.space5)
            }
            HStack(spacing: Ink.space3) {
                AppLogo(side: 44)
                VStack(alignment: .leading, spacing: Ink.titleDescGap) {
                    DTWordmark(size: 18)
                    Text(AppVersion.label)
                        .font(Ink.mono(11))
                        .foregroundStyle(Ink.secondary)
                }
            }
            Text("This beta is free and open source.")
                .font(Ink.bodyFont)
                .foregroundStyle(Ink.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var readyBody: some View {
        VStack(alignment: .leading, spacing: Ink.space5) {
            InkCard {
                InkWavePenMotif(inked: true)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Ink.space5)
            }
            Text("\(settings.chord.display) starts a session and stops it. While da transcribuh is saving or transcribing, the icon changes so you can see it working.")
                .font(Ink.bodyFont)
                .foregroundStyle(Ink.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var permissionsCard: some View {
        VStack(alignment: .leading, spacing: Ink.space3) {
            InkCard {
                VStack(alignment: .leading, spacing: 0) {
                    permissionRow(
                        title: "Microphone",
                        detail: "Hears your voice for the transcript.",
                        on: permissions.status.microphone,
                        recovery: Permissions.microphoneNeedsSettings()
                            ? "Denied — use Turn On, enable da transcribuh, then Reopen."
                            : nil
                    )
                    InkDivider(leading: 0)
                    permissionRow(
                        title: "Screen Recording",
                        detail: "Captures the tiles you drag while talking.",
                        on: permissions.status.screen,
                        recovery: permissions.status.screen
                            ? nil
                            : "If the switch is already on, turn it off and on, then Reopen."
                    )
                    InkDivider(leading: 0)
                    permissionRow(
                        title: "Accessibility",
                        detail: "Watches the shortcut and Shift for drawing.",
                        on: permissions.status.accessibility,
                        recovery: permissions.status.accessibility
                            ? nil
                            : "da transcribuh must appear in the list. Turn On prompts for that, then Reopen."
                    )
                }
            }
            Text("After you change a switch in System Settings, Reopen so da transcribuh picks it up.")
                .font(Ink.captionFont)
                .foregroundStyle(Ink.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: Ink.space2) {
                Button("Turn On") {
                    Task {
                        _ = await Permissions.requestMicrophone()
                        Permissions.revealSettings(for: Permissions.current())
                        permissions.refresh()
                    }
                }
                .buttonStyle(InkSecondaryButtonStyle())
                Button("Reopen") {
                    Permissions.relaunch()
                }
                .buttonStyle(InkSecondaryButtonStyle())
            }
            if permissions.status.isReady {
                HStack(spacing: Ink.space2) {
                    InkCheck(done: true)
                    Text("All three are on. Continue.")
                        .font(Ink.buttonSmallFont)
                        .foregroundStyle(Ink.label)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func permissionRow(title: String, detail: String, on: Bool, recovery: String?) -> some View {
        HStack(alignment: .top, spacing: Ink.space3) {
            InkCheck(done: on)
            VStack(alignment: .leading, spacing: Ink.titleDescGap) {
                HStack {
                    Text(title)
                        .font(Ink.rowTitleFont)
                        .foregroundStyle(Ink.label)
                    Spacer()
                    Text(on ? "On" : "Off")
                        .font(Ink.captionFont)
                        .foregroundStyle(Ink.secondary)
                }
                Text(detail)
                    .font(Ink.captionFont)
                    .foregroundStyle(Ink.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if let recovery, !on {
                    Text(recovery)
                        .font(Ink.captionFont)
                        .foregroundStyle(Ink.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(.horizontal, Ink.rowHPad)
        .padding(.vertical, Ink.rowVPad)
    }

    private var shortcutCard: some View {
        VStack(alignment: .leading, spacing: Ink.space3) {
            Text("The menu bar repeats this chord so you can find it later.")
                .font(Ink.bodyFont)
                .foregroundStyle(Ink.secondary)
                .fixedSize(horizontal: false, vertical: true)
            InkCard {
                VStack(spacing: Ink.space4) {
                    InkKeycapRow(keys: settings.chord.keycaps)
                    HStack(spacing: Ink.space2) {
                        Button(listening ? "Listening" : "Change") {
                            listening = true
                            shortcutNote = nil
                        }
                        .buttonStyle(InkSecondaryButtonStyle())
                        .disabled(listening)
                        Button("Use ⌥Space") {
                            listening = false
                            shortcutNote = settings.setChord(.default) ? nil : "macOS would not register that shortcut."
                        }
                        .buttonStyle(InkSecondaryButtonStyle())
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(Ink.cardPad)
            }
            Text("Hold the chord instead of tapping if you turn on push-to-talk later in General.")
                .font(Ink.captionFont)
                .foregroundStyle(Ink.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if let shortcutNote {
                InkErrorBanner(message: shortcutNote)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var modelCard: some View {
        VStack(alignment: .leading, spacing: Ink.space3) {
            Text("The first download can take a minute on a slow network. Keep this window open.")
                .font(Ink.bodyFont)
                .foregroundStyle(Ink.secondary)
                .fixedSize(horizontal: false, vertical: true)
            SpeechModelPicker(settings: settings, transfer: transfer, horizontalTiles: false)
            if transfer.isWorking, let fraction = transfer.fraction {
                VStack(alignment: .leading, spacing: Ink.space2) {
                    InkProgressBar(fraction: fraction)
                    Text("Downloading \(Int((fraction * 100).rounded()))%. Keep this window open.")
                        .font(Ink.captionFont)
                        .foregroundStyle(Ink.secondary)
                }
            } else if modelIsReady {
                HStack(spacing: Ink.space2) {
                    InkCheck(done: true)
                    Text("Selected model is on this Mac. Continue when you are ready.")
                        .font(Ink.buttonSmallFont)
                        .foregroundStyle(Ink.label)
                }
            } else {
                Text("Press Download to fetch the selected model, then Continue.")
                    .font(Ink.captionFont)
                    .foregroundStyle(Ink.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var practiceCard: some View {
        VStack(alignment: .leading, spacing: Ink.space3) {
            InkCard {
                VStack(alignment: .leading, spacing: 0) {
                    guideRow("1", "Talk for a few seconds, or stay quiet — both paths are fine.")
                    InkDivider(leading: 0)
                    guideRow("2", "Drag a rectangle to capture the front window when you want a tile.")
                    InkDivider(leading: 0)
                    guideRow("3", "Hold Shift to annotate. Release Shift to save that tile.")
                }
            }
            Text("da transcribuh stops after about five seconds and shows what happened.")
                .font(Ink.bodyFont)
                .foregroundStyle(Ink.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if !permissions.status.isReady {
                Text("Permissions are still off. Go Back and turn them on, then Reopen if needed.")
                    .font(Ink.captionFont)
                    .foregroundStyle(Ink.secondary)
            } else if !modelIsReady {
                Text("The speech model is not on disk yet. Go Back and download it.")
                    .font(Ink.captionFont)
                    .foregroundStyle(Ink.secondary)
            }
            HStack(spacing: Ink.space2) {
                Button(practiceRunning ? practiceLiveTitle : "Try a 5-second session") {
                    startPractice()
                }
                .buttonStyle(InkPrimaryButtonStyle(large: true, enabled: !practiceRunning && !session.isBusy && practiceAllowed))
                .disabled(practiceRunning || session.isBusy || !practiceAllowed)
                if practiceRunning {
                    Button("Cancel") {
                        cancelPractice()
                    }
                    .buttonStyle(InkSecondaryButtonStyle())
                }
            }
            if let practiceOutcome {
                Text(practiceOutcome)
                    .font(Ink.captionFont)
                    .foregroundStyle(Ink.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else if practiceRunning, let live = session.menuStatusLine, !live.isEmpty {
                Text(live)
                    .font(Ink.captionFont)
                    .foregroundStyle(Ink.secondary)
            }
            Text("You can skip this and try later from Home or the menu bar.")
                .font(Ink.captionFont)
                .foregroundStyle(Ink.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
        return step == .ready ? "open da transcribuh" : "Continue"
    }

    private func primaryAction() {
        if step == .model, !modelIsReady {
            transfer.download(settings.speechModel)
            return
        }
        advance()
    }

    private func guideRow(_ number: String, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Ink.space3) {
            Text(number)
                .font(Ink.headingFont)
                .foregroundStyle(Ink.label)
                .frame(width: 16, alignment: .leading)
            Text(text)
                .font(Ink.bodyFont)
                .foregroundStyle(Ink.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, Ink.rowHPad)
        .padding(.vertical, Ink.rowVPad)
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

    /// Exposed so shared chrome (traffic lights) can resolve the host window.
    var attachedWindow: NSWindow? { window }

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
        window.title = "welcome to da transcribuh"
        window.isReleasedWhenClosed = false
        window.backgroundColor = Ink.windowNSColor
        window.contentView = host
        window.setContentSize(NSSize(width: OnboardingMetrics.width, height: OnboardingMetrics.height))
        window.center()
        self.window = window
        return window
    }
}
