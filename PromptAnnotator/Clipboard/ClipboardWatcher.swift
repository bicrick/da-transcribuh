import AppKit
import Foundation

/// Polls `NSPasteboard.general.changeCount`. Cheap; stays off session hot paths.
///
/// Idle wakeups: a fixed 0.5 s poll woke the app twice a second forever. Now it
/// polls every 1.5 s while the pasteboard is quiet and drops to 0.5 s for 20 s
/// after any change, so copy bursts are sampled as before. It also checks at once
/// when the frontmost app changes (copy, then switch apps is the common path),
/// so a quiet-mode copy is caught at the switch, not up to 1.5 s later.
@MainActor
final class ClipboardWatcher {
    private var timer: Timer?
    private var lastChangeCount: Int = -1
    private var activationObserver: NSObjectProtocol?
    private var fastUntil: CFTimeInterval = 0
    private var fast = false
    static let quietInterval: TimeInterval = 1.5
    static let burstInterval: TimeInterval = 0.5
    static let burstWindow: CFTimeInterval = 20
    private let store: ClipboardHistoryStore
    var isEnabled: () -> Bool = { true }

    init(store: ClipboardHistoryStore = .shared) {
        self.store = store
    }

    func start() {
        guard timer == nil else { return }
        lastChangeCount = NSPasteboard.general.changeCount
        schedule(fast: false)
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.tick()
            }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        if let activationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(activationObserver)
        }
        activationObserver = nil
    }

    private func schedule(fast: Bool) {
        timer?.invalidate()
        self.fast = fast
        let interval = fast ? Self.burstInterval : Self.quietInterval
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.tick()
            }
        }
        timer.tolerance = fast ? 0.1 : 0.3
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    /// Fast polling after a change, back to quiet once the burst window passes.
    private func adjustRate(changed: Bool) {
        guard timer != nil else { return }
        let now = CACurrentMediaTime()
        if changed {
            fastUntil = now + Self.burstWindow
            if !fast { schedule(fast: true) }
        } else if fast, now > fastUntil {
            schedule(fast: false)
        }
    }

    /// Call when an own-write suppress nest ends so the next tick does not
    /// re-capture the pasteboard we just wrote.
    func acknowledgePasteboard() {
        lastChangeCount = NSPasteboard.general.changeCount
    }

    /// Sample now. The panel calls this on open, so a copy made in the last
    /// quiet interval is listed even without an app switch.
    func checkNow() {
        guard timer != nil else { return }
        tick()
    }

    private func tick() {
        guard isEnabled() else { return }
        let settings = AppSettings.shared
        guard !settings.clipboardCapturePaused else {
            acknowledgePasteboard()
            return
        }
        guard store.suppressWatcher == 0 else {
            acknowledgePasteboard()
            return
        }
        let board = NSPasteboard.general
        let count = board.changeCount
        guard count != lastChangeCount else {
            adjustRate(changed: false)
            return
        }
        lastChangeCount = count
        adjustRate(changed: true)
        capture(from: board)
    }

    /// PNG bytes for the board's image. Screenshots and most apps already offer
    /// public.png, so those bytes are stored as-is. The old path always decoded to
    /// NSImage, re-encoded TIFF, then re-encoded PNG on the main thread (~120 ms for
    /// a 3456x2234 screenshot). Only TIFF-only boards still pay for the conversion.
    static func pngData(from board: NSPasteboard) -> Data? {
        if let png = board.data(forType: .png), png.starts(with: [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]) {
            return png
        }
        guard let image = NSImage(pasteboard: board),
              let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .png, properties: [:])
    }

    func capture(from board: NSPasteboard) {
        let settings = AppSettings.shared
        if settings.clipboardIgnoreConcealed, ClipboardPasteboardTypes.isSensitive(board) { return }

        if let frontID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier,
           settings.clipboardIgnoredApps.contains(frontID) {
            return
        }

        if settings.clipboardSaveFiles,
           let urls = board.readObjects(forClasses: [NSURL.self], options: [
            .urlReadingFileURLsOnly: true
           ]) as? [URL], !urls.isEmpty {
            let paths = urls.map(\.path)
            _ = store.ingest(
                kind: .fileURL,
                source: .pasteboard,
                text: paths.joined(separator: "\n"),
                imagePNG: nil,
                filePaths: paths,
                fingerprint: ClipboardFingerprint.files(paths),
                applicationName: NSWorkspace.shared.frontmostApplication?.localizedName
            )
            return
        }

        if settings.clipboardSaveImages, let png = Self.pngData(from: board) {
            _ = store.ingest(
                kind: .image,
                source: .pasteboard,
                text: nil,
                imagePNG: png,
                filePaths: nil,
                fingerprint: ClipboardFingerprint.image(png),
                applicationName: NSWorkspace.shared.frontmostApplication?.localizedName
            )
            return
        }

        guard settings.clipboardSaveText else { return }

        if let str = board.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines),
           !str.isEmpty {
            _ = store.ingest(
                kind: .text,
                source: .pasteboard,
                text: str,
                imagePNG: nil,
                filePaths: nil,
                fingerprint: ClipboardFingerprint.text(str),
                applicationName: NSWorkspace.shared.frontmostApplication?.localizedName
            )
            return
        }

        // RTF → plain
        if let rtf = board.data(forType: .rtf),
           let attr = try? NSAttributedString(
            data: rtf,
            options: [.documentType: NSAttributedString.DocumentType.rtf],
            documentAttributes: nil
           ) {
            let str = attr.string.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !str.isEmpty else { return }
            _ = store.ingest(
                kind: .text,
                source: .pasteboard,
                text: str,
                imagePNG: nil,
                filePaths: nil,
                fingerprint: ClipboardFingerprint.text(str),
                applicationName: NSWorkspace.shared.frontmostApplication?.localizedName
            )
        }
    }
}
