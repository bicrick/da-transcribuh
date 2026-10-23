import AppKit

/// While push to talk is on, releasing the shortcut key ends the session.
@MainActor
final class PushToTalk {
    static let shared = PushToTalk()

    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var armed = false
    private var keyCode: UInt16 = 0

    var isArmed: Bool { armed }

    func arm(keyCode: UInt16) {
        self.keyCode = keyCode
        armed = true
        install()
    }

    func disarm() {
        armed = false
        if let globalMonitor {
            NSEvent.removeMonitor(globalMonitor)
            self.globalMonitor = nil
        }
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
            self.localMonitor = nil
        }
    }

    private func install() {
        guard globalMonitor == nil else { return }
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyUp) { [weak self] event in
            // Global monitors are delivered on the main thread.
            MainActor.assumeIsolated {
                self?.released(event)
            }
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyUp) { [weak self] event in
            MainActor.assumeIsolated {
                self?.released(event)
            }
            return event
        }
    }

    private func released(_ event: NSEvent) {
        guard armed, event.keyCode == keyCode else { return }
        armed = false
        StopTrace.noteTrigger(uptime: event.timestamp)
        SessionController.shared.releasePushToTalk()
    }
}
