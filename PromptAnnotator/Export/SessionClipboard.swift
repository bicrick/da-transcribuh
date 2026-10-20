import AppKit

enum SessionClipboard {
    /// Puts the tile sheet and the transcript on one clipboard item.
    /// Rich-text apps paste the picture and the words together. A plain text
    /// field pastes the words. An image well pastes the picture.
    @discardableResult
    static func copy(image: NSImage?, transcript: String, to board: NSPasteboard = .general) -> Bool {
        let text = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        let attributed = attributedPaste(image: image, transcript: text)
        guard attributed.length > 0 else { return false }

        let range = NSRange(location: 0, length: attributed.length)
        let rtfd = try? attributed.data(
            from: range,
            documentAttributes: [.documentType: NSAttributedString.DocumentType.rtfd]
        )
        let rtf = try? attributed.data(
            from: range,
            documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]
        )
        let png = pngData(from: image)
        let html = htmlPaste(png: png, transcript: text)

        let item = NSPasteboardItem()
        if let rtfd {
            item.setData(rtfd, forType: .rtfd)
        }
        if let rtf {
            item.setData(rtf, forType: .rtf)
        }
        if !html.isEmpty {
            item.setString(html, forType: .html)
        }
        if !text.isEmpty {
            item.setString(text, forType: .string)
        }
        if let png {
            item.setData(png, forType: .png)
        }
        if let tiff = image?.tiffRepresentation {
            item.setData(tiff, forType: .tiff)
        }

        board.clearContents()
        return board.writeObjects([item])
    }

    static func attributedPaste(image: NSImage?, transcript: String) -> NSAttributedString {
        let result = NSMutableAttributedString()
        if let image {
            let attachment = NSTextAttachment()
            attachment.image = image
            let size = image.size
            if size.width > 0, size.height > 0 {
                let maxWidth: CGFloat = 720
                let scale = size.width > maxWidth ? maxWidth / size.width : 1
                attachment.bounds = CGRect(x: 0, y: 0, width: size.width * scale, height: size.height * scale)
            }
            result.append(NSAttributedString(attachment: attachment))
        }
        if !transcript.isEmpty {
            if result.length > 0 {
                result.append(NSAttributedString(string: "\n\n"))
            }
            result.append(NSAttributedString(
                string: transcript,
                attributes: [.font: NSFont.systemFont(ofSize: NSFont.systemFontSize)]
            ))
        }
        return result
    }

    private static func pngData(from image: NSImage?) -> Data? {
        guard let image,
              let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .png, properties: [:])
    }

    private static func htmlPaste(png: Data?, transcript: String) -> String {
        var html = ""
        if let png {
            html += "<img src=\"data:image/png;base64,\(png.base64EncodedString())\" alt=\"\">"
        }
        if !transcript.isEmpty {
            let escaped = transcript
                .replacingOccurrences(of: "&", with: "&amp;")
                .replacingOccurrences(of: "<", with: "&lt;")
                .replacingOccurrences(of: ">", with: "&gt;")
                .replacingOccurrences(of: "\n", with: "<br>")
            html += "<p>\(escaped)</p>"
        }
        return html
    }
}
