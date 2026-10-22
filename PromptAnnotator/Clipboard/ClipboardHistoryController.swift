import AppKit
import Carbon.HIToolbox
import Foundation

/// Owns watcher, Carbon hotkey (id 4), panel, and paste-back.
@MainActor
final class ClipboardHistoryController {
    static let shared = ClipboardHistoryController()

    let store = ClipboardHistoryStore.shared
    private let watcher = ClipboardWatcher()
    private var hotKey: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?
    private let signature: OSType = 0x5041_6E6E // 'PAnn'
    /// Carbon id under `'PAnn'`: record=1, paste=2, cancel=3, clipboard=4.
    static let carbonHotKeyID: UInt32 = 4
    private let hotKeyID: UInt32 = ClipboardHistoryController.carbonHotKeyID

    func install() {
        guard !Runtime.isUnitTest else { return }
        watcher.isEnabled = { AppSettings.shared.clipboardHistoryEnabled }
        watcher.start()
        installHotKey(AppSettings.shared.clipboardChord)
    }

    func remove() {
        watcher.stop()
        if let hotKey {
            UnregisterEventHotKey(hotKey)
            self.hotKey = nil
        }
        if let eventHandler {
            RemoveEventHandler(eventHandler)
            self.eventHandler = nil
        }
        ClipboardHistoryPanelController.shared.hide()
    }

    @discardableResult
    func applyHotkey(_ chord: HotkeyChord) -> Bool {
        guard chord.canRegister(allowingShift: true) else { return false }
        // Persist settings in tests without registering a Carbon hotkey.
        if Runtime.isUnitTest { return true }
        if let hotKey {
            UnregisterEventHotKey(hotKey)
            self.hotKey = nil
        }
        installHandlerIfNeeded()
        var registered: EventHotKeyRef?
        let id = EventHotKeyID(signature: signature, id: hotKeyID)
        let status = RegisterEventHotKey(
            chord.keyCode,
            chord.normalizedModifiers,
            id,
            GetApplicationEventTarget(),
            0,
            &registered
        )
        guard status == noErr else { return false }
        hotKey = registered
        return true
    }

    func togglePanel() {
        guard AppSettings.shared.clipboardHistoryEnabled else { return }
        ClipboardHistoryPanelController.shared.toggle()
    }

    /// Write item to the pasteboard; optionally simulate ⌘V into the frontmost app.
    func pick(_ item: ClipboardItem, paste: Bool) {
        store.beginOwnWrite()
        defer { store.endOwnWrite() }

        switch item.kind {
        case .text:
            let text = item.text ?? ""
            _ = SessionClipboard.writeTranscript(text, to: .general)
        case .image:
            if let image = store.image(for: item),
               let tiff = image.tiffRepresentation,
               let rep = NSBitmapImageRep(data: tiff),
               let png = rep.representation(using: .png, properties: [:]) {
                _ = SessionClipboard.writeImage(png: png, tiff: tiff, to: .general)
            }
        case .fileURL:
            let urls = (item.filePaths ?? []).map { URL(fileURLWithPath: $0) as NSURL }
            let board = NSPasteboard.general
            board.clearContents()
            board.writeObjects(urls)
        }

        if paste {
            PasteFollowUp.shared.simulateCommandV()
        }
    }

    /// Session transcript / screenshot ingest (tagged). Skips empty quiet takes.
    func ingestSession(transcript: String?, imagePNG: Data?) {
        if ClipboardEmptySession.shouldSkip(transcript: transcript, imagePNG: imagePNG) {
            return
        }
        if let imagePNG, !imagePNG.isEmpty {
            _ = store.ingest(
                kind: .image,
                source: .screenshot,
                text: nil,
                imagePNG: imagePNG,
                filePaths: nil,
                fingerprint: ClipboardFingerprint.image(imagePNG),
                applicationName: "da transcribuh"
            )
        }
        let text = transcript?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let scrubbed = NonSpeechFilter.scrub(text).trimmingCharacters(in: .whitespacesAndNewlines)
        if !scrubbed.isEmpty {
            _ = store.ingest(
                kind: .text,
                source: .transcript,
                text: scrubbed,
                imagePNG: nil,
                filePaths: nil,
                fingerprint: ClipboardFingerprint.text(scrubbed),
                applicationName: "da transcribuh"
            )
        }
    }

    private func installHotKey(_ chord: HotkeyChord) {
        _ = applyHotkey(chord)
    }

    private func installHandlerIfNeeded() {
        guard eventHandler == nil else { return }
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
                let controller = Unmanaged<ClipboardHistoryController>.fromOpaque(userData).takeUnretainedValue()
                guard pressed.signature == controller.signature, pressed.id == controller.hotKeyID else {
                    return OSStatus(eventNotHandledErr)
                }
                DispatchQueue.main.async {
                    MainActor.assumeIsolated {
                        controller.togglePanel()
                    }
                }
                return noErr
            },
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandler
        )
    }
}
