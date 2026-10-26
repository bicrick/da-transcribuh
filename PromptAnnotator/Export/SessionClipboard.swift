import AppKit

enum SessionClipboard {
    /// Stages a finished take. A collage with words goes up as one linked entry:
    /// two pasteboard items (picture, then words), so a manual ⌘V into an app
    /// that reads every item gets both. When da transcribuh pastes for you it
    /// does not rely on that: `PasteFollowUp` pastes the picture, then the words.
    /// The ⌘V follow-up is not armed for linked boards, since an app that took
    /// both items would get the words twice.
    @discardableResult
    static func copy(image: NSImage?, transcript: String, to board: NSPasteboard = .general) -> Bool {
        let text = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        let png = pngData(from: image)
        if let png {
            let tiff = image?.tiffRepresentation
            if !text.isEmpty {
                guard writeLinked(png: png, tiff: tiff, text: text, to: board) else { return false }
            } else {
                guard writeImage(png: png, tiff: tiff, to: board) else { return false }
            }
            if board === NSPasteboard.general {
                let changeCount = board.changeCount
                MainActor.assumeIsolated {
                    if text.isEmpty {
                        PasteFollowUp.shared.arm(png: png, tiff: tiff, transcript: text, changeCount: changeCount)
                    } else {
                        PasteFollowUp.shared.armLinked(png: png, tiff: tiff, transcript: text, changeCount: changeCount)
                    }
                    ClipboardHistoryController.shared.ingestSession(transcript: text, imagePNG: png)
                }
            }
            return true
        }
        guard !text.isEmpty else { return false }
        guard writeTranscript(text, to: board) else { return false }
        if board === NSPasteboard.general {
            let changeCount = board.changeCount
            MainActor.assumeIsolated {
                PasteFollowUp.shared.arm(png: nil, tiff: nil, transcript: text, changeCount: changeCount)
                ClipboardHistoryController.shared.ingestSession(transcript: text, imagePNG: nil)
            }
        }
        return true
    }

    /// Restages a take for a held paste (no text field had focus) or Copy Last
    /// Again. Image plus words go up as the linked two-item board, so ⌘V keeps
    /// both where the target reads every item. Does **not** arm the ⌘V
    /// follow-up (that would double the words); `PasteFollowUp` keeps the
    /// payload for ⌃⌥V, which pastes the picture and then the words.
    @discardableResult
    static func stageCombined(image: NSImage?, transcript: String, to board: NSPasteboard = .general) -> Bool {
        let text = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        let png = pngData(from: image)
        guard png != nil || !text.isEmpty else { return false }
        let isGeneral = board === NSPasteboard.general
        let tiff = image?.tiffRepresentation

        if let png {
            let wrote = text.isEmpty
                ? writeImage(png: png, tiff: tiff, to: board)
                : writeLinked(png: png, tiff: tiff, text: text, to: board)
            guard wrote else { return false }
            if isGeneral {
                MainActor.assumeIsolated {
                    PasteFollowUp.shared.armPending(png: png, tiff: tiff, transcript: text)
                    ClipboardHistoryController.shared.ingestSession(transcript: text, imagePNG: png)
                }
            }
            return true
        }

        guard writeTranscript(text, to: board) else { return false }
        if isGeneral {
            MainActor.assumeIsolated {
                PasteFollowUp.shared.armPending(png: nil, tiff: nil, transcript: text)
                ClipboardHistoryController.shared.ingestSession(transcript: text, imagePNG: nil)
            }
        }
        return true
    }

    /// The linked collage + transcript entry as two pasteboard items.
    ///
    /// Item 1 is the picture: PNG, TIFF, and an image-only RTFD so rich Cocoa
    /// editors (TextEdit, Notes) insert it. Item 2 is the words as plain text.
    /// Measured on macOS 26: a rich NSTextView reads both items (picture, then
    /// words), a plain field reads the words, and Chrome's paste event exposes
    /// both `text/plain` and the PNG file. No HTML or RTF of the words: Chrome
    /// prefers HTML over the image when either is present.
    @discardableResult
    static func writeLinked(png: Data, tiff: Data?, text: String, to board: NSPasteboard) -> Bool {
        if board === NSPasteboard.general {
            MainActor.assumeIsolated { ClipboardHistoryStore.shared.beginOwnWrite() }
        }
        defer {
            if board === NSPasteboard.general {
                MainActor.assumeIsolated { ClipboardHistoryStore.shared.endOwnWrite() }
            }
        }
        board.clearContents()
        let picture = NSPasteboardItem()
        picture.setData(png, forType: .png)
        if let tiff {
            picture.setData(tiff, forType: .tiff)
        }
        if let rtfd = rtfdImageOnly(png: png) {
            picture.setData(rtfd, forType: .rtfd)
        }
        let words = NSPasteboardItem()
        words.setString(text, forType: .string)
        return board.writeObjects([picture, words])
    }

    /// RTFD holding just the picture. Wraps the PNG bytes as-is (no TIFF
    /// re-encode), so it costs about a copy of the PNG.
    static func rtfdImageOnly(png: Data) -> Data? {
        let wrapper = FileWrapper(regularFileWithContents: png)
        wrapper.preferredFilename = "collage.png"
        let attachment = NSTextAttachment(fileWrapper: wrapper)
        let string = NSAttributedString(attachment: attachment)
        return try? string.data(
            from: NSRange(location: 0, length: string.length),
            documentAttributes: [.documentType: NSAttributedString.DocumentType.rtfd]
        )
    }

    @discardableResult
    static func writeImage(png: Data, tiff: Data?, to board: NSPasteboard) -> Bool {
        if board === NSPasteboard.general {
            MainActor.assumeIsolated { ClipboardHistoryStore.shared.beginOwnWrite() }
        }
        defer {
            if board === NSPasteboard.general {
                MainActor.assumeIsolated { ClipboardHistoryStore.shared.endOwnWrite() }
            }
        }
        board.clearContents()
        guard board.setData(png, forType: .png) else { return false }
        if let tiff {
            board.setData(tiff, forType: .tiff)
        }
        return true
    }

    /// Pastes a mixed history item back as one pasteboard item with every type:
    /// PNG and TIFF for image targets, plain text for text fields, and RTFD (image
    /// then text) for rich editors unless "paste without formatting" is on.
    @discardableResult
    static func writeMixed(text: String, png: Data, plainOnly: Bool, to board: NSPasteboard) -> Bool {
        if board === NSPasteboard.general {
            MainActor.assumeIsolated { ClipboardHistoryStore.shared.beginOwnWrite() }
        }
        defer {
            if board === NSPasteboard.general {
                MainActor.assumeIsolated { ClipboardHistoryStore.shared.endOwnWrite() }
            }
        }
        board.clearContents()
        let item = NSPasteboardItem()
        item.setData(png, forType: .png)
        let image = NSImage(data: png)
        if let tiff = image?.tiffRepresentation {
            item.setData(tiff, forType: .tiff)
        }
        item.setString(text, forType: .string)
        if !plainOnly, let image, let rtfd = rtfdData(image: image, text: text) {
            item.setData(rtfd, forType: .rtfd)
        }
        return board.writeObjects([item])
    }

    @discardableResult
    static func writeTranscript(_ text: String, to board: NSPasteboard) -> Bool {
        writeClipboardText(text, plainOnly: true, to: board)
    }

    /// Stages history text for paste-back. When `plainOnly` is false, also
    /// declares RTF so destinations that prefer rich paste get a typed payload.
    @discardableResult
    static func writeClipboardText(_ text: String, plainOnly: Bool, to board: NSPasteboard) -> Bool {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        if board === NSPasteboard.general {
            MainActor.assumeIsolated { ClipboardHistoryStore.shared.beginOwnWrite() }
        }
        defer {
            if board === NSPasteboard.general {
                MainActor.assumeIsolated { ClipboardHistoryStore.shared.endOwnWrite() }
            }
        }
        board.clearContents()
        if plainOnly {
            return board.setString(text, forType: .string)
        }
        let attr = NSAttributedString(
            string: text,
            attributes: [.font: NSFont.systemFont(ofSize: 13)]
        )
        if let rtf = try? attr.data(
            from: NSRange(location: 0, length: attr.length),
            documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]
        ) {
            board.declareTypes([.string, .rtf], owner: nil)
            board.setString(text, forType: .string)
            board.setData(rtf, forType: .rtf)
            return true
        }
        return board.setString(text, forType: .string)
    }

    static func pngData(from image: NSImage?) -> Data? {
        guard let image,
              let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .png, properties: [:])
    }

    static func rtfdData(image: NSImage, text: String) -> Data? {
        let attachment = NSTextAttachment()
        attachment.image = image
        let combined = NSMutableAttributedString(attributedString: NSAttributedString(attachment: attachment))
        let spacer = text.hasPrefix("\n") ? "" : "\n"
        combined.append(NSAttributedString(
            string: spacer + text,
            attributes: [.font: NSFont.systemFont(ofSize: 13)]
        ))
        return try? combined.data(
            from: NSRange(location: 0, length: combined.length),
            documentAttributes: [
                .documentType: NSAttributedString.DocumentType.rtfd,
            ]
        )
    }
}
