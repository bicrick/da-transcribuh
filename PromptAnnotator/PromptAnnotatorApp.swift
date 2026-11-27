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

    var body: some Scene {
        // The menu bar item + borderless square panel live in `DTMenuBarController`
        // (avoids macOS 26/27 Liquid Glass rounded-corner clipping on `MenuBarExtra(.window)`).
        Settings {
            EmptyView()
        }
        .commands {
            CommandGroup(replacing: .appSettings) {
                Button("Settings…") {
                    SettingsPresenter.shared.show()
                }
                .keyboardShortcut(",", modifiers: .command)
            }
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        PerfSuite.launchMark("didFinishLaunching")
        // Fonts before any chrome paints — Departure Mono for every wordmark / label.
        InkFontRegistrar.registerBundledFonts()
        guard !Runtime.isUnitTest else { return }
        _ = DiagnosticsExporter.launchDate
        AppLog.info("launch \(AppVersion.label) macOS \(ProcessInfo.processInfo.operatingSystemVersionString) at \(Bundle.main.bundlePath)")
        AppSettings.shared.appearance.applyToApp()
        HotkeyCenter.shared.onActivation = { action in
            SessionController.shared.handleActivation(action)
        }
        HotkeyCenter.shared.handler = {
            SessionController.shared.handleHotkey()
        }
        HotkeyCenter.shared.cancelHandler = {
            SessionController.shared.cancel()
        }
        let settings = AppSettings.shared
        HotkeyCenter.shared.install(settings.chord, behavior: settings.hotkeyBehavior)
        PerfHarness.runPanelCycle()
        VerifyNavHarness.run()
        PanelSnapshotHarness.run()
        HotkeyCenter.shared.applyCancel(settings.cancelChord)
        settings.onAppChange = {
            SettingsPresenter.shared.applyChrome()
            DockPresence.apply(show: AppSettings.shared.showInDock)
        }
        DispatchQueue.main.async {
            DockPresence.apply(show: settings.showInDock)
        }
        PasteFollowUp.shared.install()
        // Sparkle. Automatic checks are off in Info.plist; this only wires up the manual check.
        MainActor.assumeIsolated {
            UpdateController.shared.start()
            StayAwakeController.shared.refreshSystemState()
            DTMenuBarController.shared.install()
        }
        ClipboardHistoryController.shared.install()
        // Drop empty (no text, no images) sessions left from older builds — once.
        SessionEmptyTake.runOneTimeCleanupIfNeeded()
        if OnboardingStore.isFinished() && !OnboardingSnapshotHarness.isActive {
            SettingsPresenter.shared.show()
        } else {
            OnboardingPresenter.shared.show()
        }
        PerfSuite.start()
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
        defer { ClipboardHistoryStore.flushPendingWrites() }
        HotkeyCenter.shared.remove()
        MainActor.assumeIsolated {
            if AppSettings.shared.clipboardClearOnQuit {
                ClipboardHistoryStore.shared.clearHistoryFully(
                    clearSystem: AppSettings.shared.clipboardClearSystemClipboard
                )
            }
            PasteFollowUp.shared.remove()
            ClipboardHistoryController.shared.remove()
        }
        MainActor.assumeIsolated {
            DTMenuBarController.shared.remove()
            StayAwakeController.shared.shutdown()
            SessionController.shared.abandonIfRecording()
        }
    }
}
