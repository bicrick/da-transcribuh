import Carbon.HIToolbox
import Foundation

/// Control-Option-Space, as a tap. Option-Space, Command-Space, and
/// Option-Command-Space are left alone because this chord requires both modifiers.
final class HotkeyCenter {
    static let shared = HotkeyCenter()

    var handler: (() -> Void)?
    var cancelHandler: (() -> Void)?

    private var hotKey: EventHotKeyRef?
    private var cancelKey: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?
    private var chord = HotkeyChord.default
    private let signature: OSType = 0x5041_6E6E // 'PAnn'
    private let hotKeyID: UInt32 = 1
    private let cancelID: UInt32 = 3

    @discardableResult
    func install(_ chord: HotkeyChord) -> Bool {
        installHandlerIfNeeded()
        return register(chord)
    }

    @discardableResult
    func apply(_ chord: HotkeyChord) -> Bool {
        guard eventHandler != nil else {
            self.chord = chord
            return true
        }
        let previous = self.chord
        guard register(chord) else {
            _ = register(previous)
            return false
        }
        self.chord = chord
        return true
    }

    @discardableResult
    func applyCancel(_ chord: HotkeyChord?) -> Bool {
        installHandlerIfNeeded()
        if let cancelKey {
            UnregisterEventHotKey(cancelKey)
            self.cancelKey = nil
        }
        guard let chord else { return true }
        guard chord.canRegister else { return false }
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

    private func installHandlerIfNeeded() {
        guard eventHandler == nil else { return }
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, userData -> OSStatus in
                // noErr means "handled". The paste shortcut shares this event
                // class, so a mismatch has to fall through to that handler.
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
                    DispatchQueue.main.async {
                        center.handler?()
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
                return noErr
            },
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandler
        )
        _ = status
    }

    @discardableResult
    private func register(_ chord: HotkeyChord) -> Bool {
        guard chord.canRegister else { return false }
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
        if status == noErr {
            self.chord = chord
        }
        return status == noErr
    }

    func remove() {
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
}
