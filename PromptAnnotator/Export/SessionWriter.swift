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
        lines.append("# da transcribuh")
        lines.append("")
        lines.append("Started: \(started)")
        lines.append("Ended: \(ended)")
        if let model {
            lines.append("Model: \(model)")
        }
        lines.append("")

        if sections.isEmpty {
            let spoken = Aligner.spokenText(transcript)
            if !spoken.isEmpty {
                lines.append(spoken)
                lines.append("")
            }
        }

        for section in sections {
            let spoken = Aligner.spokenText(section.words)
            let closing = Aligner.spokenText(section.closingNote)
            // A timestamp is only there to match a picture with the comment about it.
            if !spoken.isEmpty || !closing.isEmpty {
                lines.append("## \(section.index) · \(TimeFormat.clock(section.commitOffset))")
                lines.append("")
            }
            lines.append("![\(section.index)](\(section.imagePath))")
            lines.append("")
            if !spoken.isEmpty {
                lines.append(spoken)
                lines.append("")
            }
            if !closing.isEmpty {
                lines.append("Closing note:")
                lines.append("")
                lines.append(closing)
                lines.append("")
            }
        }

        if let transcriptionError, !transcriptionError.isEmpty {
            lines.append("Transcription failed: \(transcriptionError)")
            lines.append("")
        }

        return lines.joined(separator: "\n")
    }

    static func containsSpeech(_ sections: [Section]) -> Bool {
        sections.contains { !spoken(in: $0).isEmpty }
    }

    static func pasteText(
        sections: [Section],
        transcript: [TimedWord],
        transcriptionError: String?
    ) -> String {
        var paragraphs: [String] = []
        if sections.isEmpty {
            let all = Aligner.spokenText(transcript)
            if !all.isEmpty {
                paragraphs.append(all)
            }
        } else if containsSpeech(sections) {
            // The number matches that tile's badge. A silent tile has no comment,
            // so it stays out of the paste. Nothing said means the picture alone.
            for section in sections {
                let spoken = spoken(in: section)
                guard !spoken.isEmpty else { continue }
                paragraphs.append("\(section.index). \(spoken)")
            }
        }
        if let transcriptionError, !transcriptionError.isEmpty {
            paragraphs.append("Transcription failed: \(transcriptionError)")
        }
        return paragraphs.joined(separator: "\n\n")
    }

    private static func spoken(in section: Section) -> String {
        [Aligner.spokenText(section.words), Aligner.spokenText(section.closingNote)]
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }
}

enum SessionPaths {
    static func sessionsRoot() throws -> URL {
        try SessionStore.root()
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
    /// Synchronous ImageIO encode + write. Prefer `writeAsync` on the capture hot path
    /// so MainActor is not blocked by PNG compression.
    static func write(_ image: CGImage, to url: URL) throws {
        try CapturePerf.interval(.encode) {
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

    /// Encode and write on a utility-QoS queue (never the audio real-time path).
    static func writeAsync(_ image: CGImage, to url: URL) async throws {
        try await CapturePerf.intervalAsync(.write) {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                DispatchQueue.global(qos: .utility).async {
                    do {
                        try write(image, to: url)
                        continuation.resume()
                    } catch {
                        continuation.resume(throwing: error)
                    }
                }
            }
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
        let showCaptions = SessionMarkdown.containsSpeech(sections)
        if let sheet = CapturePerf.interval(.thumbnail, {
            ContactSheet.render(
                images: images,
                commitOffsets: offsets,
                showCaptions: showCaptions
            )
        }) {
            let url = directory.appendingPathComponent("sheet.png")
            try PNG.write(sheet, to: url)
            sheetURL = url
        }

        return Saved(directory: directory, notes: notes, pasteText: pasteText, sheetURL: sheetURL)
    }

    /// Session finalize + contact-sheet thumbnail off MainActor (utility QoS).
    static func writeAsync(
        directory: URL,
        started: Date,
        ended: Date,
        groups: [ExportGroup],
        words: [TimedWord],
        model: String?,
        transcriptionError: String?
    ) async throws -> Saved {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Saved, Error>) in
            DispatchQueue.global(qos: .utility).async {
                do {
                    let saved = try write(
                        directory: directory,
                        started: started,
                        ended: ended,
                        groups: groups,
                        words: words,
                        model: model,
                        transcriptionError: transcriptionError
                    )
                    continuation.resume(returning: saved)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
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
