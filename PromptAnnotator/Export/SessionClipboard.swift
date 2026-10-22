import AppKit

enum SessionClipboard {
    /// Stages the tile sheet by itself. Chat and browser text boxes take the
    /// picture and drop the words when both are on the clipboard at once.
    /// `PasteFollowUp` pastes the words on the next Paste.
    @discardableResult
    static func copy(image: NSImage?, transcript: String, to board: NSPasteboard = .general) -> Bool {
        let text = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        let png = pngData(from: image)
        if let png {
            guard writeImage(png: png, tiff: image?.tiffRepresentation, to: board) else { return false }
            if board === NSPasteboard.general {
                let changeCount = board.changeCount
                MainActor.assumeIsolated {
                    PasteFollowUp.shared.arm(
                        png: png,
                        tiff: image?.tiffRepresentation,
                        transcript: text,
                        changeCount: changeCount
                    )
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
            }
        }
        return true
    }

    /// Stages image + text together for ⌘V into apps that accept RTFD/HTML, with
    /// plain-text and PNG fallbacks. Used when auto-paste is held (no text field).
    /// Does **not** arm the sequential ⌘V image→text follow-up (that would double-paste
    /// in RTFD apps); `PasteFollowUp` still keeps the payload for ⌃⌥V / Copy Last Again.
    @discardableResult
    static func stageCombined(image: NSImage?, transcript: String, to board: NSPasteboard = .general) -> Bool {
        let text = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        let png = pngData(from: image)
        guard png != nil || !text.isEmpty else { return false }

        board.clearContents()

        if let png, let image, !text.isEmpty {
            let item = NSPasteboardItem()
            item.setData(png, forType: .png)
            if let tiff = image.tiffRepresentation {
                item.setData(tiff, forType: .tiff)
            }
            item.setString(text, forType: .string)
            if let rtfd = rtfdData(image: image, text: text) {
                item.setData(rtfd, forType: .rtfd)
            }
            if let html = htmlData(png: png, text: text) {
                item.setData(html, forType: .html)
            }
            guard board.writeObjects([item]) else { return false }
            if board === NSPasteboard.general {
                MainActor.assumeIsolated {
                    PasteFollowUp.shared.armPending(
                        png: png,
                        tiff: image.tiffRepresentation,
                        transcript: text
                    )
                }
            }
            return true
        }

        if let png {
            guard writeImage(png: png, tiff: image?.tiffRepresentation, to: board) else { return false }
            if board === NSPasteboard.general {
                MainActor.assumeIsolated {
                    PasteFollowUp.shared.armPending(
                        png: png,
                        tiff: image?.tiffRepresentation,
                        transcript: text
                    )
                }
            }
            return true
        }

        guard writeTranscript(text, to: board) else { return false }
        if board === NSPasteboard.general {
            MainActor.assumeIsolated {
                PasteFollowUp.shared.armPending(png: nil, tiff: nil, transcript: text)
            }
        }
        return true
    }

    @discardableResult
    static func writeImage(png: Data, tiff: Data?, to board: NSPasteboard) -> Bool {
        board.clearContents()
        guard board.setData(png, forType: .png) else { return false }
        if let tiff {
            board.setData(tiff, forType: .tiff)
        }
        return true
    }

    @discardableResult
    static func writeTranscript(_ text: String, to board: NSPasteboard) -> Bool {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        board.clearContents()
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

    static func htmlData(png: Data, text: String) -> Data? {
        let base64 = png.base64EncodedString()
        let escaped = text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\n", with: "<br>\n")
        let html = """
        <meta charset="utf-8">
        <img src="data:image/png;base64,\(base64)"><br>\(escaped)
        """
        return html.data(using: .utf8)
    }
}
