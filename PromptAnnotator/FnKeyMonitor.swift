import AppKit

/// Watches bare Globe/fn (`kVK_Function` / 0x3F) via `flagsChanged`.
/// Bare fn does not produce keyDown; Carbon cannot register it.
/// Does **not** rewrite `AppleFnUsageType` — instruct the user to set
/// Keyboard → Press 🌐 key to → Do Nothing (see research report).
final class FnKeyMonitor {
    var onDown: ((TimeInterval) -> Void)?
    var onUp: ((TimeInterval) -> Void)?
    /// Another key or non-fn modifier while fn is held (Wispr interrupted-start).
    var onInterrupted: (() -> Void)?

    private var globalFlags: Any?
    private var localFlags: Any?
    private var globalKeys: Any?
    private var localKeys: Any?
    private var fnDown = false

    var isDown: Bool { fnDown }

    func start() {
        guard globalFlags == nil else { return }
        let flagsMask: NSEvent.EventTypeMask = .flagsChanged
        globalFlags = NSEvent.addGlobalMonitorForEvents(matching: flagsMask) { [weak self] event in
            MainActor.assumeIsolated { self?.handleFlags(event) }
        }
        localFlags = NSEvent.addLocalMonitorForEvents(matching: flagsMask) { [weak self] event in
            MainActor.assumeIsolated { self?.handleFlags(event) }
            return event
        }
        let keyMask: NSEvent.EventTypeMask = [.keyDown, .keyUp]
        globalKeys = NSEvent.addGlobalMonitorForEvents(matching: keyMask) { [weak self] event in
            MainActor.assumeIsolated { self?.handleKey(event) }
        }
        localKeys = NSEvent.addLocalMonitorForEvents(matching: keyMask) { [weak self] event in
            MainActor.assumeIsolated { self?.handleKey(event) }
            return event
        }
    }

    func stop() {
        if let globalFlags { NSEvent.removeMonitor(globalFlags); self.globalFlags = nil }
        if let localFlags { NSEvent.removeMonitor(localFlags); self.localFlags = nil }
        if let globalKeys { NSEvent.removeMonitor(globalKeys); self.globalKeys = nil }
        if let localKeys { NSEvent.removeMonitor(localKeys); self.localKeys = nil }
        fnDown = false
    }

    private func handleFlags(_ event: NSEvent) {
        if event.keyCode == UInt16(HotkeyChord.fnKeyCode) {
            // `.function` tracks the physical fn/Globe down state.
            let down = event.modifierFlags.contains(.function)
            if down, !fnDown {
                fnDown = true
                onDown?(event.timestamp)
            } else if !down, fnDown {
                fnDown = false
                onUp?(event.timestamp)
            }
            return
        }
        // A different modifier changed while fn is held → treat as interrupt.
        if fnDown {
            interrupt()
        }
    }

    private func handleKey(_ event: NSEvent) {
        guard fnDown, event.type == .keyDown else { return }
        // Ignore repeats; any other physical key cancels the held start.
        if event.isARepeat { return }
        interrupt()
    }

    private func interrupt() {
        guard fnDown else { return }
        fnDown = false
        onInterrupted?()
    }
}
