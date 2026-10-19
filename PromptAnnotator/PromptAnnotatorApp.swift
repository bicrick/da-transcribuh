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
            AppMenuMark(recording: session.phase == .recording)
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
        HotkeyCenter.shared.handler = {
            SessionController.shared.toggle()
        }
        HotkeyCenter.shared.install(AppSettings.shared.chord)
        SettingsPresenter.shared.showOnFirstLaunch()
    }

    func applicationWillTerminate(_ notification: Notification) {
        HotkeyCenter.shared.remove()
        MainActor.assumeIsolated {
            SessionController.shared.abandonIfRecording()
        }
    }
}
