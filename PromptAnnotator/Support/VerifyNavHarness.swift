import AppKit
import SwiftUI

/// Launch with `-DTVerifyNav <dir>` to check that clipboard prefs are reachable.
/// It leaves Settings on Home and hidden, opens the clipboard panel, and
/// posts a real ⌘, key event into the app's queue (the panel's key monitor
/// handles it). Then it snapshots Settings, renders the menu bar panel, and quits.
@MainActor
enum VerifyNavHarness {
    static func run() {
        guard let dir = UserDefaults.standard.string(forKey: "DTVerifyNav") else { return }
        func log(_ s: String) { FileHandle.standardError.write(Data("dtverify \(s)\n".utf8)) }
        func after(_ ms: Int, _ body: @escaping @MainActor () -> Void) {
            DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(ms)) { MainActor.assumeIsolated(body) }
        }
        after(2500) {
            SettingsPresenter.shared.show(page: .home)
            after(800) {
                snap(SettingsPresenter.shared.attachedWindow, "\(dir)/nav-0-home.png", log)
                SettingsPresenter.shared.attachedWindow?.orderOut(nil)
                ClipboardHistoryPanelController.shared.show()
                after(800) {
                    let panel = NSApp.windows.first { $0.isVisible && $0 !== SettingsPresenter.shared.attachedWindow && $0.canBecomeKey }
                    log("panel visible=\(panel != nil) key=\(NSApp.keyWindow === panel)")
                    if let panel,
                       let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: .command,
                                                    timestamp: ProcessInfo.processInfo.systemUptime,
                                                    windowNumber: panel.windowNumber, context: nil,
                                                    characters: ",", charactersIgnoringModifiers: ",",
                                                    isARepeat: false, keyCode: 43) {
                        NSApp.postEvent(event, atStart: false)
                    }
                    after(1200) {
                        let w = SettingsPresenter.shared.attachedWindow
                        log("settings visible=\(w?.isVisible ?? false) panelVisible=\(panel?.isVisible ?? false)")
                        snap(w, "\(dir)/nav-1-after-cmd-comma.png", log)
                        let host = NSHostingView(rootView: DTMenuBarPanel(session: SessionController.shared, settings: AppSettings.shared))
                        host.frame = NSRect(origin: .zero, size: host.fittingSize)
                        let offscreen = NSWindow(contentRect: host.frame, styleMask: .borderless, backing: .buffered, defer: false)
                        offscreen.contentView = host
                        host.layoutSubtreeIfNeeded()
                        after(500) {
                            write(host, "\(dir)/menubar-panel.png", log)
                            log("done")
                            NSApp.terminate(nil)
                        }
                    }
                }
            }
        }
    }

    private static func snap(_ window: NSWindow?, _ path: String, _ log: (String) -> Void) {
        guard let view = window?.contentView?.superview ?? window?.contentView else { log("no window for \(path)"); return }
        write(view, path, log)
    }

    private static func write(_ view: NSView, _ path: String, _ log: (String) -> Void) {
        guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
        log("wrote \(path)")
    }
}
