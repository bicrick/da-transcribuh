import AppKit
import Foundation
import ImageIO
import UniformTypeIdentifiers

struct ExportGroup {
    var index: Int
    var committedAt: TimeInterval
    var display: DisplaySnapshot
    var shapes: [AnnotationShape]
    var image: CGImage
}

struct SessionMarkdown {
    struct Section: Equatable {
        var index: Int
        var commitOffset: TimeInterval
        var imagePath: String
        var words: [TimedWord]
        var closingNote: [TimedWord]
    }

    static func render(
        started: String,
        ended: String,
        model: String?,
        sections: [Section],
        transcript: [TimedWord],
        transcriptionError: String?
    ) -> String {
        var lines: [String] = []
        lines.append("# Prompt Annotator")
        lines.append("")
        lines.append("Started: \(started)")
        lines.append("Ended: \(ended)")
        if let model {
            lines.append("Model: \(model)")
        }
        lines.append("")

        for section in sections {
            lines.append("## \(section.index) · \(TimeFormat.clock(section.commitOffset))")
            lines.append("")
            lines.append("![\(section.index)](\(section.imagePath))")
            lines.append("")
            let spoken = Aligner.spokenText(section.words)
            if !spoken.isEmpty {
                lines.append(spoken)
                lines.append("")
            }
            let closing = Aligner.spokenText(section.closingNote)
            if !closing.isEmpty {
                lines.append("Closing note:")
                lines.append("")
                lines.append(closing)
                lines.append("")
            }
        }

        lines.append("## Transcript")
        lines.append("")
        if let transcriptionError {
            lines.append("Transcription failed: \(transcriptionError)")
            lines.append("")
        }
        if transcript.isEmpty {
            lines.append("No speech detected.")
            lines.append("")
        } else {
            for word in transcript {
                let token = word.text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !token.isEmpty else { continue }
                lines.append("[\(TimeFormat.precise(word.start))] \(token)")
            }
            lines.append("")
        }

        return lines.joined(separator: "\n")
    }

    static func pasteText(
        sections: [Section],
        transcript: [TimedWord],
        transcriptionError: String?
    ) -> String {
        var paragraphs: [String] = []
        for section in sections {
            let spoken = [Aligner.spokenText(section.words), Aligner.spokenText(section.closingNote)]
                .filter { !$0.isEmpty }
                .joined(separator: " ")
            if !spoken.isEmpty {
                paragraphs.append(spoken)
            }
        }
        if paragraphs.isEmpty {
            let all = Aligner.spokenText(transcript)
            if !all.isEmpty {
                paragraphs.append(all)
            }
        }
        if let transcriptionError, !transcriptionError.isEmpty {
            paragraphs.append("Transcription failed: \(transcriptionError)")
        }
        return paragraphs.joined(separator: "\n\n")
    }
}

enum SessionPaths {
    static func sessionsRoot() throws -> URL {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let root = documents.appendingPathComponent("PromptAnnotator/Sessions", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    static func makeSessionDirectory(at date: Date) throws -> URL {
        let root = try sessionsRoot()
        let stamp = Stamp.folder.string(from: date)
        var url = root.appendingPathComponent(stamp, isDirectory: true)
        var suffix = 2
        while FileManager.default.fileExists(atPath: url.path) {
            url = root.appendingPathComponent("\(stamp)-\(suffix)", isDirectory: true)
            suffix += 1
        }
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(
            at: url.appendingPathComponent("frames", isDirectory: true),
            withIntermediateDirectories: true
        )
        return url
    }
}

enum PNG {
    static func write(_ image: CGImage, to url: URL) throws {
        let folder = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
            throw ExportError("Couldn't open \(url.lastPathComponent) for writing.")
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw ExportError("Couldn't write \(url.lastPathComponent).")
        }
    }
}

struct ExportError: LocalizedError {
    var message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}

enum SessionWriter {
    struct Saved {
        var directory: URL
        var notes: String
        var pasteText: String
        var sheetURL: URL?
    }

    static func write(
        directory: URL,
        started: Date,
        ended: Date,
        groups: [ExportGroup],
        words: [TimedWord],
        model: String?,
        transcriptionError: String?
    ) throws -> Saved {
        let commitTimes = groups.map(\.committedAt)
        let sessionEnd = max(0, ended.timeIntervalSince(started))
        let aligned = Aligner.align(words: words, commitTimes: commitTimes, sessionEnd: sessionEnd)

        var sections: [SessionMarkdown.Section] = []
        var jsonGroups: [GroupDocument] = []

        for (offset, group) in groups.enumerated() {
            let match = offset < aligned.count ? aligned[offset] : Aligner.Group(words: [], closingNote: [])
            let fileName = String(format: "frames/%02d.png", group.index)
            sections.append(
                SessionMarkdown.Section(
                    index: group.index,
                    commitOffset: group.committedAt,
                    imagePath: fileName,
                    words: match.words,
                    closingNote: match.closingNote
                )
            )
            jsonGroups.append(
                GroupDocument(
                    index: group.index,
                    committedAt: group.committedAt,
                    frame: fileName,
                    display: group.display,
                    shapes: group.shapes.map(ShapeRecord.init),
                    words: match.words,
                    closingNote: match.closingNote
                )
            )
        }

        let pasteText = SessionMarkdown.pasteText(
            sections: sections,
            transcript: words.sorted { $0.start < $1.start },
            transcriptionError: transcriptionError
        )
        let notes = SessionMarkdown.render(
            started: Stamp.readable.string(from: started),
            ended: Stamp.readable.string(from: ended),
            model: model,
            sections: sections,
            transcript: words.sorted { $0.start < $1.start },
            transcriptionError: transcriptionError
        )
        try notes.write(to: directory.appendingPathComponent("session.md"), atomically: true, encoding: .utf8)

        let document = SessionDocument(
            version: 1,
            startedAt: Stamp.iso.string(from: started),
            endedAt: Stamp.iso.string(from: ended),
            coordinateSpace: "display points, origin top-left, y down",
            model: model,
            transcriptionError: transcriptionError,
            words: words,
            groups: jsonGroups
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(document)
        try data.write(to: directory.appendingPathComponent("session.json"), options: .atomic)

        var sheetURL: URL?
        let images = groups.map(\.image)
        let offsets = groups.map(\.committedAt)
        if let sheet = ContactSheet.render(images: images, commitOffsets: offsets) {
            let url = directory.appendingPathComponent("sheet.png")
            try PNG.write(sheet, to: url)
            sheetURL = url
        }

        return Saved(directory: directory, notes: notes, pasteText: pasteText, sheetURL: sheetURL)
    }
}

struct GroupDocument: Codable, Equatable {
    var index: Int
    var committedAt: TimeInterval
    var frame: String
    var display: DisplaySnapshot
    var shapes: [ShapeRecord]
    var words: [TimedWord]
    var closingNote: [TimedWord]
}

struct SessionDocument: Codable, Equatable {
    var version: Int
    var startedAt: String
    var endedAt: String
    var coordinateSpace: String
    var model: String?
    var transcriptionError: String?
    var words: [TimedWord]
    var groups: [GroupDocument]
}
