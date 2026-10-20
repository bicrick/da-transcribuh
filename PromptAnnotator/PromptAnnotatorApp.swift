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
            // A system image plus a short title. A custom drawing in this label
            // does not show up in the menu bar, so the app looks like it is not running.
            Label(
                session.phase == .recording ? "Rec" : "PA",
                systemImage: session.phase == .recording ? "record.circle.fill" : "pencil.tip.crop.circle"
            )
        }
    }
}

private struct SessionMenu: View {
    @ObservedObject var session: SessionController
    @ObservedObject var settings: AppSettings

    var body: some View {
        Button("Open Prompt Annotator") {
            SettingsPresenter.shared.show()
        }

        Divider()

        Button(session.toggleTitle) {
            session.toggle()
        }
        .disabled(session.isBusy)

        Text("Shortcut: \(settings.chord.display)")

        if session.isBusy {
            Text(session.statusText)
        }

        if let lastError = session.lastError, session.phase != .recording {
            Text(lastError)
        }

        Divider()

        if session.lastSessionURL != nil {
            Button("Paste Image and Text (\(PasteFollowUp.shortcut))") {
                PasteFollowUp.shared.pasteBoth()
            }
            Button("Show Last Session in Finder") {
                session.revealSession()
            }
        }

        Button("Quit Prompt Annotator") {
            NSApp.terminate(nil)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        guard !Runtime.isUnitTest else { return }
        // MenuBarExtra would otherwise keep this as an agent, which hides the Dock icon.
        DispatchQueue.main.async {
            NSApp.setActivationPolicy(.regular)
        }
        HotkeyCenter.shared.handler = {
            SessionController.shared.toggle()
        }
        HotkeyCenter.shared.install(AppSettings.shared.chord)
        PasteFollowUp.shared.install()
        SettingsPresenter.shared.show()
        Task { @MainActor in
            SessionController.shared.prepareModel()
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        guard !Runtime.isUnitTest else { return true }
        if !flag {
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
