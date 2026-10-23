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
    /// public.png, so those bytes are stored as-is. Only TIFF-only (or PDF-only)
    /// boards pay for a conversion.
    static func pngData(from board: NSPasteboard) -> Data? {
        ClipboardCapture.anyImagePNG(from: board)
    }

    func capture(from board: NSPasteboard) {
        let settings = AppSettings.shared
        if settings.clipboardIgnoreConcealed, ClipboardPasteboardTypes.isSensitive(board) { return }

        if let frontID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier,
           settings.clipboardIgnoredApps.contains(frontID) {
            return
        }

        guard let payload = ClipboardCapture.payload(
            from: board,
            saveFiles: settings.clipboardSaveFiles,
            saveImages: settings.clipboardSaveImages,
            saveText: settings.clipboardSaveText
        ) else { return }
        _ = store.ingest(
            payload: payload,
            source: .pasteboard,
            applicationName: NSWorkspace.shared.frontmostApplication?.localizedName
        )
    }
}

/// What one pasteboard change is stored as.
enum ClipboardCapturePayload: Equatable {
    case files([String])
    case image(png: Data)
    case text(String)
    /// One copy that offered both text and a bitmap (web page, Notes, Excel).
    case mixed(text: String, png: Data)
}

/// Reads a pasteboard into a payload. Pure apart from the board, so tests drive it
/// with a private `NSPasteboard(name:)`.
///
/// Before mixed items, an image on the board returned early and any text that came
/// with it was dropped. A text copy from Pages or Keynote (which adds a PDF) was
/// even stored as a picture of the text. Now:
/// - files win, as before;
/// - text plus a real bitmap (public.png, public.tiff, or an image inside RTFD)
///   is one mixed item;
/// - text plus only a PDF rendering is text;
/// - an image with no text is an image (PDF-only still converts, as before).
enum ClipboardCapture {
    static let pngMagic: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]

    static func payload(
        from board: NSPasteboard,
        saveFiles: Bool,
        saveImages: Bool,
        saveText: Bool
    ) -> ClipboardCapturePayload? {
        if saveFiles,
           let urls = board.readObjects(forClasses: [NSURL.self], options: [
            .urlReadingFileURLsOnly: true
           ]) as? [URL], !urls.isEmpty {
            return .files(urls.map(\.path))
        }
        let text = saveText ? plainText(from: board) : nil
        if saveImages {
            if let text {
                if let png = bitmapPNG(from: board) { return .mixed(text: text, png: png) }
            } else if let png = anyImagePNG(from: board) {
                return .image(png: png)
            }
        }
        if let text { return .text(text) }
        return nil
    }

    /// Plain text from the board: the string type, else RTF, else RTFD (minus the
    /// attachment placeholder characters). Trimmed; nil when empty.
    static func plainText(from board: NSPasteboard) -> String? {
        if let str = board.string(forType: .string).flatMap(trimmed) { return str }
        if let rtf = board.data(forType: .rtf),
           let attr = try? NSAttributedString(
            data: rtf,
            options: [.documentType: NSAttributedString.DocumentType.rtf],
            documentAttributes: nil
           ),
           let str = trimmed(attr.string) {
            return str
        }
        if let rtfd = board.data(forType: .rtfd),
           let attr = NSAttributedString(rtfd: rtfd, documentAttributes: nil),
           let str = trimmed(attr.string.replacingOccurrences(of: "\u{FFFC}", with: "")) {
            return str
        }
        return nil
    }

    /// A real bitmap on the board as PNG: public.png as-is, other bytes under the
    /// PNG type decoded, TIFF converted, else the first image attached in RTFD.
    /// Ignores PDF, which text apps add as a rendering of the words.
    static func bitmapPNG(from board: NSPasteboard) -> Data? {
        if let raw = board.data(forType: .png) {
            if raw.starts(with: pngMagic) { return raw }
            if let png = png(fromImageData: raw) { return png }
        }
        if let tiff = board.data(forType: .tiff), let png = png(fromImageData: tiff) {
            return png
        }
        if let rtfd = board.data(forType: .rtfd), let png = firstAttachmentPNG(rtfd: rtfd) {
            return png
        }
        return nil
    }

    /// Any image on the board as PNG, including what `NSImage(pasteboard:)` can
    /// read (PDF). Used when the copy has no text.
    static func anyImagePNG(from board: NSPasteboard) -> Data? {
        if let png = bitmapPNG(from: board) { return png }
        guard let image = NSImage(pasteboard: board),
              let tiff = image.tiffRepresentation else { return nil }
        return png(fromImageData: tiff)
    }

    static func png(fromImageData data: Data) -> Data? {
        if data.starts(with: pngMagic) { return data }
        guard let rep = NSBitmapImageRep(data: data) else { return nil }
        return rep.representation(using: .png, properties: [:])
    }

    /// First bitmap attachment in flat RTFD (TextEdit, Notes, Mail copies).
    static func firstAttachmentPNG(rtfd: Data) -> Data? {
        guard let attr = NSAttributedString(rtfd: rtfd, documentAttributes: nil),
              attr.length > 0 else { return nil }
        var found: Data?
        attr.enumerateAttribute(.attachment, in: NSRange(location: 0, length: attr.length)) { value, _, stop in
            guard let attachment = value as? NSTextAttachment else { return }
            if let contents = attachment.fileWrapper?.regularFileContents ?? attachment.contents,
               let png = png(fromImageData: contents) {
                found = png
            } else if let tiff = attachment.image?.tiffRepresentation, let png = png(fromImageData: tiff) {
                found = png
            }
            if found != nil { stop.pointee = true }
        }
        return found
    }

    private static func trimmed(_ string: String) -> String? {
        let out = string.trimmingCharacters(in: .whitespacesAndNewlines)
        return out.isEmpty ? nil : out
    }
}
