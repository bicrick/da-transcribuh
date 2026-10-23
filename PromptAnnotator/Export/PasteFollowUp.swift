import AppKit
import Carbon.HIToolbox
import CoreGraphics

enum PasteKey {
    static let vKeyCode = UInt16(kVK_ANSI_V)

    static func isCommandV(keyCode: UInt16, modifiers: NSEvent.ModifierFlags, isRepeat: Bool) -> Bool {
        guard !isRepeat, keyCode == vKeyCode else { return false }
        let mods = modifiers.intersection(.deviceIndependentFlagsMask)
        guard mods.contains(.command) else { return false }
        return !mods.contains(.control) && !mods.contains(.option)
    }
}

/// After the picture is on the clipboard, the next Command-V pastes it, and
/// this posts a second Command-V with the words. Control-Option-V does both.
@MainActor
final class PasteFollowUp {
    static let shared = PasteFollowUp()
    static let shortcut = "⌃⌥V"
    static let readyHint = "Ready to paste: press ⌃⌥V or ⌘V in any text field"

    private var png: Data?
    private var tiff: Data?
    private var transcript = ""
    private var armedChangeCount: Int?
    private var delivering = false
    private var commandVIsDown = false
    private var followUp: DispatchWorkItem?
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var hotKey: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?
    private let signature: OSType = 0x5041_6E6E
    private let hotKeyID: UInt32 = 2

    /// Session output is staged but auto-paste was held (no text field).
    private(set) var isAwaitingPaste = false

    var canReplay: Bool {
        png != nil || !transcript.isEmpty
    }

    /// Optional hook so SessionController can clear / refresh menu status.
    var onAwaitingPasteChange: ((Bool) -> Void)?

    func install() {
        guard !Runtime.isUnitTest else { return }
        installMonitors()
        installHotKey()
    }

    func remove() {
        followUp?.cancel()
        if let globalMonitor {
            NSEvent.removeMonitor(globalMonitor)
            self.globalMonitor = nil
        }
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
            self.localMonitor = nil
        }
        if let hotKey {
            UnregisterEventHotKey(hotKey)
            self.hotKey = nil
        }
        if let eventHandler {
            RemoveEventHandler(eventHandler)
            self.eventHandler = nil
        }
    }

    func arm(png: Data?, tiff: Data?, transcript: String, changeCount: Int) {
        self.png = png
        self.tiff = tiff
        self.transcript = transcript
        armedChangeCount = (png != nil && !transcript.isEmpty) ? changeCount : nil
        // Image-then-text staging is for immediate / sequential paste — not a held pending.
        setAwaitingPaste(false)
    }

    /// Keep payload for ⌃⌥V / Copy Last Again without arming the ⌘V image→text follow-up.
    func armPending(png: Data?, tiff: Data?, transcript: String) {
        self.png = png
        self.tiff = tiff
        self.transcript = transcript
        armedChangeCount = nil
        setAwaitingPaste(true)
    }

    func clearAwaitingPaste() {
        setAwaitingPaste(false)
    }

    private func setAwaitingPaste(_ value: Bool) {
        guard isAwaitingPaste != value else { return }
        isAwaitingPaste = value
        onAwaitingPasteChange?(value)
    }

    /// Restores the last staged image / transcript after another app overwrote the pasteboard.
    @discardableResult
    func restoreClipboard() -> Bool {
        guard canReplay else { return false }
        if let png {
            // Prefer combined staging when both sides exist so ⌘V keeps images + text.
            if !transcript.isEmpty,
               let image = NSImage(data: png) ?? (tiff.flatMap { NSImage(data: $0) }) {
                guard SessionClipboard.stageCombined(image: image, transcript: transcript) else {
                    guard SessionClipboard.writeImage(png: png, tiff: tiff, to: .general) else { return false }
                    armPending(png: png, tiff: tiff, transcript: transcript)
                    return true
                }
                return true
            }
            guard SessionClipboard.writeImage(png: png, tiff: tiff, to: .general) else { return false }
            armPending(png: png, tiff: tiff, transcript: transcript)
            return true
        }
        guard SessionClipboard.writeTranscript(transcript, to: .general) else { return false }
        armPending(png: nil, tiff: nil, transcript: transcript)
        return true
    }

    func pasteBoth() {
        let image = png
        let words = transcript
        guard !delivering else { return }
        guard image != nil || !words.isEmpty else { return }
        followUp?.cancel()
        followUp = nil
        commandVIsDown = false
        delivering = true
        armedChangeCount = nil
        setAwaitingPaste(false)

        guard let image else {
            _ = SessionClipboard.writeTranscript(words, to: .general)
            postCommandV()
            scheduleIdle()
            return
        }

        _ = SessionClipboard.writeImage(png: image, tiff: tiff, to: .general)
        postCommandV()
        guard !words.isEmpty else {
            scheduleIdle()
            return
        }
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            _ = SessionClipboard.writeTranscript("\n" + words, to: .general)
            self.postCommandV()
            self.scheduleIdle()
        }
        followUp = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: work)
    }

    private func installMonitors() {
        guard globalMonitor == nil else { return }
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.keyDown, .keyUp]) { [weak self] event in
            MainActor.assumeIsolated {
                self?.note(event)
            }
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp]) { [weak self] event in
            MainActor.assumeIsolated {
                self?.note(event)
            }
            return event
        }
    }

    private func installHotKey() {
        guard hotKey == nil else { return }
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        InstallEventHandler(
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
                let followUp = Unmanaged<PasteFollowUp>.fromOpaque(userData).takeUnretainedValue()
                guard pressed.signature == followUp.signature, pressed.id == followUp.hotKeyID else {
                    return OSStatus(eventNotHandledErr)
                }
                DispatchQueue.main.async {
                    MainActor.assumeIsolated {
                        followUp.pasteBoth()
                    }
                }
                return noErr
            },
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandler
        )
        let id = EventHotKeyID(signature: signature, id: hotKeyID)
        RegisterEventHotKey(
            UInt32(kVK_ANSI_V),
            UInt32(controlKey | optionKey),
            id,
            GetApplicationEventTarget(),
            0,
            &hotKey
        )
    }

    private func note(_ event: NSEvent) {
        guard !delivering else { return }
        if event.type == .keyDown {
            guard PasteKey.isCommandV(keyCode: event.keyCode, modifiers: event.modifierFlags, isRepeat: event.isARepeat) else {
                return
            }
            commandVIsDown = true
            return
        }
        guard event.type == .keyUp, event.keyCode == UInt16(kVK_ANSI_V), commandVIsDown else { return }
        commandVIsDown = false
        scheduleTranscript()
    }

    private func scheduleTranscript() {
        guard followUp == nil, let expected = armedChangeCount, !transcript.isEmpty else { return }
        guard NSPasteboard.general.changeCount == expected else {
            armedChangeCount = nil
            return
        }
        let words = transcript
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.followUp = nil
            guard NSPasteboard.general.changeCount == expected else {
                self.armedChangeCount = nil
                return
            }
            self.delivering = true
            self.armedChangeCount = nil
            self.setAwaitingPaste(false)
            _ = SessionClipboard.writeTranscript("\n" + words, to: .general)
            self.postCommandV()
            self.scheduleIdle()
        }
        followUp = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: work)
    }

    private func scheduleIdle() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.delivering = false
        }
    }

    /// Public entry for clipboard history / callers that already staged the pasteboard.
    func simulateCommandV() {
        postCommandV()
    }

    private func postCommandV() {
        // A full chord: ⌘ down, V down, V up, ⌘ up. Posting only V with the ⌘ flag left
        // the HID system state reporting ⌘ held after every paste, so the next synthetic
        // Return went out as ⌘Return and the modifier gate waited its full 250 ms.
        let source = CGEventSource(stateID: .hidSystemState)
        let command = CGKeyCode(kVK_Command)
        let key = CGKeyCode(kVK_ANSI_V)
        let events: [(CGKeyCode, Bool, CGEventFlags)] = [
            (command, true, .maskCommand),
            (key, true, .maskCommand),
            (key, false, .maskCommand),
            (command, false, []),
        ]
        for (code, isDown, flags) in events {
            let event = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: isDown)
            event?.flags = flags
            event?.post(tap: .cghidEventTap)
        }
    }
}
