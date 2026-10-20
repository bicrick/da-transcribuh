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
                    PasteFollowUp.shared.arm(png: png, tiff: image?.tiffRepresentation, transcript: text, changeCount: changeCount)
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
}
