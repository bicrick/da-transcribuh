import AppKit
import SwiftUI

enum Runtime {
    static var isUnitTest: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }
}

@main
struct PromptAnnotatorApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var session = SessionController.shared

    var body: some Scene {
        MenuBarExtra {
            SessionMenu(session: session, settings: AppSettings.shared)
        } label: {
            // A system image. A custom drawing in this label does not show up in the menu bar.
            Image(systemName: session.menuIcon)
                .accessibilityLabel(session.menuAccessibilityLabel)
        }
    }
}

private struct SessionMenu: View {
    @ObservedObject var session: SessionController
    @ObservedObject var settings: AppSettings

    var body: some View {
        Button("Open Mutter") {
            SettingsPresenter.shared.show()
        }

        Divider()

        Button(session.toggleTitle) {
            session.toggle()
        }
        .disabled(session.isBusy)

        Text(shortcutHint)
            .foregroundStyle(.secondary)
        if let cancel = settings.cancelChord {
            Text("Cancel: \(cancel.display)")
                .foregroundStyle(.secondary)
        }

        if let status = session.menuStatusLine {
            Text(status)
        }

        Divider()

        if session.lastSessionURL != nil {
            Button("Paste Image and Text (\(PasteFollowUp.shortcut))") {
                PasteFollowUp.shared.pasteBoth()
            }
            .disabled(session.isBusy || session.phase == .recording)
            Button("Show Last Session in Finder") {
                session.revealSession()
            }
            .disabled(session.isBusy)
        }

        Text(AppVersion.label)
            .foregroundStyle(.secondary)

        Button("Quit Mutter") {
            NSApp.terminate(nil)
        }
    }

    private var shortcutHint: String {
        let chord = settings.chord.display
        if settings.pushToTalk {
            return "Hold \(chord) to talk"
        }
        return "\(chord) starts and stops"
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        guard !Runtime.isUnitTest else { return }
        HotkeyCenter.shared.handler = {
            SessionController.shared.handleHotkey()
        }
        HotkeyCenter.shared.cancelHandler = {
            SessionController.shared.cancel()
        }
        let settings = AppSettings.shared
        HotkeyCenter.shared.install(settings.chord)
        HotkeyCenter.shared.applyCancel(settings.cancelChord)
        settings.onAppChange = {
            SettingsPresenter.shared.applyChrome()
            DockPresence.apply(show: AppSettings.shared.showInDock)
        }
        DispatchQueue.main.async {
            DockPresence.apply(show: settings.showInDock)
        }
        PasteFollowUp.shared.install()
        if OnboardingStore.isFinished() {
            SettingsPresenter.shared.show()
        } else {
            OnboardingPresenter.shared.show()
        }
        Task { @MainActor in
            SessionController.shared.prepareModel()
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        guard !Runtime.isUnitTest else { return true }
        if !OnboardingStore.isFinished() {
            OnboardingPresenter.shared.show()
        } else if !flag {
            SettingsPresenter.shared.show()
        }
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        HotkeyCenter.shared.remove()
        MainActor.assumeIsolated {
            PasteFollowUp.shared.remove()
        }
        MainActor.assumeIsolated {
            SessionController.shared.abandonIfRecording()
        }
    }
}
