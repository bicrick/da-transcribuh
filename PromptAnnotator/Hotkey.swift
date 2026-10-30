import AppKit
import Carbon.HIToolbox
import CoreGraphics
import Foundation

/// Global Start/Stop hotkey.
/// Carbon `RegisterEventHotKey` for registrable chords; `FnKeyMonitor` for bare fn
/// (Wispr Flow–style). Hold / double-tap / toggle driven by `HotkeyActivationMachine`.
final class HotkeyCenter {
    static let shared = HotkeyCenter()

    /// Fired for start / stop / cancel from the activation machine (not timer ops).
    var onActivation: ((HotkeyActivationMachine.Action) -> Void)?
    /// Legacy: Carbon press → toggle/PTT. Prefer `onActivation`.
    var handler: (() -> Void)?
    var cancelHandler: (() -> Void)?

    /// Carbon event time (seconds since boot) of the last Start/Stop press.
    private(set) var lastPressUptime: TimeInterval = 0

    /// True while the recording shortcut is physically held (for session key masking).
    private(set) var isHolding = false

    private var hotKey: EventHotKeyRef?
    private var cancelKey: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?
    private var chord = HotkeyChord.default
    private var behavior: HotkeyBehavior = .holdAndDoubleTap
    private var machine = HotkeyActivationMachine()
    private var doubleTapWork: DispatchWorkItem?
    private var fnMonitor: FnKeyMonitor?
    private var keyUpGlobal: Any?
    private var keyUpLocal: Any?
    private var keyDownGlobal: Any?
    private var keyDownLocal: Any?
    private let signature: OSType = 0x5041_6E6E // 'PAnn'
    private let hotKeyID: UInt32 = 1
    private let cancelID: UInt32 = 3
    private var installed = false

    @discardableResult
    func install(_ chord: HotkeyChord, behavior: HotkeyBehavior = .holdAndDoubleTap) -> Bool {
        self.behavior = behavior
        installHandlerIfNeeded()
        installed = true
        return applyRegistration(chord)
    }

    @discardableResult
    func apply(_ chord: HotkeyChord, behavior: HotkeyBehavior? = nil) -> Bool {
        if let behavior {
            self.behavior = behavior
        }
        guard installed || eventHandler != nil || fnMonitor != nil else {
            self.chord = chord
            return true
        }
        let previous = self.chord
        guard applyRegistration(chord) else {
            _ = applyRegistration(previous)
            return false
        }
        return true
    }

    func applyBehavior(_ behavior: HotkeyBehavior) {
        self.behavior = behavior
        machine = HotkeyActivationMachine()
        clearDoubleTapTimer()
        isHolding = false
        // Re-bind monitors for the same chord under the new behavior.
        if installed {
            _ = applyRegistration(chord)
        }
    }

    @discardableResult
    func applyCancel(_ chord: HotkeyChord?) -> Bool {
        installHandlerIfNeeded()
        if let cancelKey {
            UnregisterEventHotKey(cancelKey)
            self.cancelKey = nil
        }
        guard let chord else { return true }
        guard chord.isCarbonRegistrable else { return false }
        var registered: EventHotKeyRef?
        let id = EventHotKeyID(signature: signature, id: cancelID)
        let status = RegisterEventHotKey(
            chord.keyCode,
            chord.normalizedModifiers,
            id,
            GetApplicationEventTarget(),
            0,
            &registered
        )
        guard status == noErr else { return false }
        cancelKey = registered
        return true
    }

    private func applyRegistration(_ chord: HotkeyChord) -> Bool {
        tearDownChordMonitors()
        machine = HotkeyActivationMachine()
        clearDoubleTapTimer()
        isHolding = false

        if chord.isFnOnly {
            // Drop Carbon hotkey if any.
            if let hotKey {
                UnregisterEventHotKey(hotKey)
                self.hotKey = nil
            }
            // Soft prompt for Input Monitoring (Wispr asks for it alongside Accessibility).
            if !CGPreflightListenEventAccess() {
                _ = CGRequestListenEventAccess()
            }
            let monitor = FnKeyMonitor()
            monitor.onDown = { [weak self] at in
                self?.edge(.down(at: at))
            }
            monitor.onUp = { [weak self] at in
                self?.edge(.up(at: at))
            }
            monitor.onInterrupted = { [weak self] in
                self?.edge(.interrupted)
            }
            monitor.start()
            fnMonitor = monitor
            self.chord = chord
            return true
        }

        guard chord.isCarbonRegistrable else { return false }
        installHandlerIfNeeded()
        if let hotKey {
            UnregisterEventHotKey(hotKey)
            self.hotKey = nil
        }
        let id = EventHotKeyID(signature: signature, id: hotKeyID)
        let status = RegisterEventHotKey(
            chord.keyCode,
            chord.normalizedModifiers,
            id,
            GetApplicationEventTarget(),
            0,
            &hotKey
        )
        guard status == noErr else { return false }
        self.chord = chord
        if behavior != .toggleOnly {
            installKeyMonitorsForHold()
        }
        return true
    }

    private func tearDownChordMonitors() {
        fnMonitor?.stop()
        fnMonitor = nil
        if let keyUpGlobal { NSEvent.removeMonitor(keyUpGlobal); self.keyUpGlobal = nil }
        if let keyUpLocal { NSEvent.removeMonitor(keyUpLocal); self.keyUpLocal = nil }
        if let keyDownGlobal { NSEvent.removeMonitor(keyDownGlobal); self.keyDownGlobal = nil }
        if let keyDownLocal { NSEvent.removeMonitor(keyDownLocal); self.keyDownLocal = nil }
    }

    /// Carbon only delivers press; hold modes need keyUp + interrupt keyDown.
    private func installKeyMonitorsForHold() {
        let code = UInt16(chord.keyCode)
        keyUpGlobal = NSEvent.addGlobalMonitorForEvents(matching: .keyUp) { [weak self] event in
            MainActor.assumeIsolated {
                guard let self, event.keyCode == code else { return }
                self.edge(.up(at: event.timestamp))
            }
        }
        keyUpLocal = NSEvent.addLocalMonitorForEvents(matching: .keyUp) { [weak self] event in
            MainActor.assumeIsolated {
                if let self, event.keyCode == code {
                    self.edge(.up(at: event.timestamp))
                }
            }
            return event
        }
        keyDownGlobal = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            MainActor.assumeIsolated {
                guard let self, self.isHolding, event.keyCode != code, !event.isARepeat else { return }
                self.edge(.interrupted)
            }
        }
        keyDownLocal = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            MainActor.assumeIsolated {
                if let self, self.isHolding, event.keyCode != code, !event.isARepeat {
                    self.edge(.interrupted)
                }
            }
            return event
        }
    }

    private func edge(_ edge: HotkeyActivationMachine.Edge) {
        switch edge {
        case .down(let at):
            lastPressUptime = at
            // Toggle does not keep a physical hold; hold modes do.
            if behavior != .toggleOnly {
                isHolding = true
            }
        case .up, .interrupted:
            isHolding = false
        case .doubleTapTimedOut:
            break
        }
        let actions = machine.handle(edge, behavior: behavior)
        dispatch(actions)
    }

    private func dispatch(_ actions: [HotkeyActivationMachine.Action]) {
        for action in actions {
            switch action {
            case .armDoubleTapTimer(let deadline):
                clearDoubleTapTimer()
                let delay = max(0, deadline - ProcessInfo.processInfo.systemUptime)
                let work = DispatchWorkItem { [weak self] in
                    self?.edge(.doubleTapTimedOut)
                }
                doubleTapWork = work
                DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
            case .cancelDoubleTapTimer:
                clearDoubleTapTimer()
            case .startRecording, .stopRecording, .cancelRecording:
                if let onActivation {
                    onActivation(action)
                } else if action == .startRecording || action == .stopRecording {
                    // Fallback for older wiring.
                    handler?()
                }
            }
        }
    }

    private func clearDoubleTapTimer() {
        doubleTapWork?.cancel()
        doubleTapWork = nil
    }

    private func installHandlerIfNeeded() {
        guard eventHandler == nil else { return }
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, userData -> OSStatus in
                guard let event, let userData else { return OSStatus(eventNotHandledErr) }
                var pressed = EventHotKeyID()
                let parameter = GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &pressed
                )
                guard parameter == noErr else { return parameter }
                let center = Unmanaged<HotkeyCenter>.fromOpaque(userData).takeUnretainedValue()
                guard pressed.signature == center.signature else {
                    return OSStatus(eventNotHandledErr)
                }
                if pressed.id == center.hotKeyID {
                    let at = GetEventTime(event)
                    DispatchQueue.main.async {
                        center.edge(.down(at: at))
                    }
                    return noErr
                }
                if pressed.id == center.cancelID {
                    DispatchQueue.main.async {
                        center.cancelHandler?()
                    }
                    return noErr
                }
                return OSStatus(eventNotHandledErr)
            },
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandler
        )
        _ = status
    }

    func remove() {
        tearDownChordMonitors()
        clearDoubleTapTimer()
        machine = HotkeyActivationMachine()
        isHolding = false
        installed = false
        if let hotKey {
            UnregisterEventHotKey(hotKey)
            self.hotKey = nil
        }
        if let cancelKey {
            UnregisterEventHotKey(cancelKey)
            self.cancelKey = nil
        }
        if let eventHandler {
            RemoveEventHandler(eventHandler)
            self.eventHandler = nil
        }
    }

    /// CGEventFlags contributed by the held recording chord (session keys ignore these).
    func heldChordFlags() -> CGEventFlags {
        guard isHolding else { return [] }
        if chord.isFnOnly {
            return .maskSecondaryFn
        }
        let mods = chord.normalizedModifiers
        var flags: CGEventFlags = []
        if mods & UInt32(shiftKey) != 0 { flags.insert(.maskShift) }
        if mods & UInt32(controlKey) != 0 { flags.insert(.maskControl) }
        if mods & UInt32(optionKey) != 0 { flags.insert(.maskAlternate) }
        if mods & UInt32(cmdKey) != 0 { flags.insert(.maskCommand) }
        return flags
    }
}
