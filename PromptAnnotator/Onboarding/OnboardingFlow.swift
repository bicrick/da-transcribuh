import AppKit
import SwiftUI

enum OnboardingStep: Int, CaseIterable {
    case welcome
    case permissions
    case shortcut
    case capture
    case ready

    var title: String {
        switch self {
        case .welcome: return "Welcome"
        case .permissions: return "Permissions"
        case .shortcut: return "Shortcut"
        case .capture: return "A session"
        case .ready: return "Ready"
        }
    }
}

struct OnboardingFlow: View {
    @ObservedObject var settings: AppSettings
    @StateObject private var permissions = PermissionModel()
    @State private var step: OnboardingStep = .welcome
    @State private var listening = false
    @State private var shortcutNote: String?
    var onFinish: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 14) {
                AppLogo(side: 56)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Prompt Annotator")
                        .font(.system(size: 20, weight: .semibold))
                    Text(AppVersion.label)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }
            Text(step.title)
                .font(.system(size: 15, weight: .semibold))
            stepBody
            Spacer(minLength: 0)
            HStack {
                Text("\(step.rawValue + 1) of \(OnboardingStep.allCases.count)")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                Spacer()
                if step != .welcome {
                    Button("Back") { retreat() }
                }
                if step != .ready {
                    Button("Skip setup") { onFinish() }
                }
                Button(step == .ready ? "Open Prompt Annotator" : "Continue") {
                    advance()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(28)
        .frame(width: 520, height: 460)
        .background(ShortcutCapture(active: $listening) { event in
            applyShortcut(event)
        })
        .onAppear { permissions.refresh() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            permissions.refresh()
        }
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
        case .capture:
            captureBody
        case .ready:
            Text("The menu bar item opens this window again. \(settings.chord.display) starts a session, and the same shortcut stops it.")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var permissionList: some View {
        VStack(alignment: .leading, spacing: 10) {
            permissionRow("Microphone", on: permissions.status.microphone)
            permissionRow("Screen Recording", on: permissions.status.screen)
            permissionRow("Accessibility", on: permissions.status.accessibility)
            Text("If a switch is already on and the app still asks, turn that switch off and on, then reopen.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Button("Turn On") {
                    Task { _ = await Permissions.requestMicrophone() }
                    Permissions.revealSettings(for: permissions.status)
                    permissions.refresh()
                }
                Button("Reopen") {
                    Permissions.relaunch()
                }
            }
        }
    }

    private func permissionRow(_ title: String, on: Bool) -> some View {
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
    }

    private var shortcutBody: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("A tap starts. A second tap stops. Shift stays free, because Shift is how you draw.")
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
            if let shortcutNote {
                Text(shortcutNote)
                    .font(.system(size: 12))
                    .foregroundStyle(.red)
            }
        }
    }

    private var captureBody: some View {
        VStack(alignment: .leading, spacing: 8) {
            guideRow("1", "Talk, or stay quiet and only take pictures.")
            guideRow("2", "Drag a rectangle to capture the front window.")
            guideRow("3", "Hold Shift to annotate. Release Shift to save that tile.")
        }
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
            onFinish()
            return
        }
        if next == .permissions {
            Task { _ = await Permissions.requestMicrophone() }
            _ = Permissions.requestScreenRecording()
            permissions.refresh()
        }
        step = next
    }

    private func retreat() {
        listening = false
        if let previous = OnboardingStep(rawValue: step.rawValue - 1) {
            step = previous
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
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 460),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Welcome to Prompt Annotator"
        window.isReleasedWhenClosed = false
        window.contentView = host
        window.center()
        self.window = window
        return window
    }
}
