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
            DTMenuBarPanel(session: session, settings: AppSettings.shared)
        } label: {
            // Template dt glyph (assets).
            Label {
                Text(session.menuAccessibilityLabel)
            } icon: {
                Image("MenuBarIcon")
                    .renderingMode(.template)
            }
            .labelStyle(.iconOnly)
            .accessibilityLabel(session.menuAccessibilityLabel)
        }
        .menuBarExtraStyle(.window)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        guard !Runtime.isUnitTest else { return }
        AppSettings.shared.appearance.applyToApp()
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
        // Let the menu bar / welcome window paint before Core ML prewarm competes for CPU.
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 450_000_000)
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
