import AppKit
import Foundation

/// Polls `NSPasteboard.general.changeCount` (~0.5s). Cheap; stays off session hot paths.
@MainActor
final class ClipboardWatcher {
    private var timer: Timer?
    private var lastChangeCount: Int = -1
    private let store: ClipboardHistoryStore
    var isEnabled: () -> Bool = { true }

    init(store: ClipboardHistoryStore = .shared) {
        self.store = store
    }

    func start() {
        guard timer == nil else { return }
        lastChangeCount = NSPasteboard.general.changeCount
        let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.tick()
            }
        }
        timer.tolerance = 0.1
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    /// Call when an own-write suppress nest ends so the next tick does not
    /// re-capture the pasteboard we just wrote.
    func acknowledgePasteboard() {
        lastChangeCount = NSPasteboard.general.changeCount
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
        guard count != lastChangeCount else { return }
        lastChangeCount = count
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
