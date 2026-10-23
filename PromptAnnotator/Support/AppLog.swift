import Foundation
import os

/// Local diagnostics log. Each line goes to the unified log (subsystem
/// `com.bicrick.PromptAnnotator`, category `app`) and to a size-capped file in
/// Application Support/PromptAnnotator/Logs, which "Export diagnostics" zips.
///
/// Lines are events and timings only: never transcript, clipboard or screen content.
/// The file rotates at `maxBytes` into one `.1` generation, so it stays under 2 × maxBytes.
enum AppLog {
    static let subsystem = "com.bicrick.PromptAnnotator"
    static let maxBytes = 512 * 1024

    private static let logger = Logger(subsystem: subsystem, category: "app")
    private static let queue = DispatchQueue(label: "com.bicrick.PromptAnnotator.applog", qos: .utility)

    static func info(_ message: String) {
        logger.info("\(message, privacy: .public)")
        write("info", message)
    }

    static func error(_ message: String) {
        logger.error("\(message, privacy: .public)")
        write("error", message)
    }

    static func folderURL() -> URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return support.appendingPathComponent("PromptAnnotator/Logs", isDirectory: true)
    }

    static var fileURL: URL { folderURL().appendingPathComponent("app.log") }

    /// Blocks until queued lines are on disk (export, tests).
    static func flush() {
        queue.sync {}
    }

    private static func write(_ level: String, _ message: String) {
        let line = "\(ISO8601DateFormatter.diagnostics.string(from: Date())) [\(level)] \(message)\n"
        let url = fileURL
        queue.async {
            append(line, to: url, maxBytes: maxBytes)
        }
    }

    /// Appends one line, first rotating `url` to `url.1` when it would pass `maxBytes`.
    static func append(_ line: String, to url: URL, maxBytes: Int) {
        let fm = FileManager.default
        guard let data = line.data(using: .utf8) else { return }
        try? fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let size = (try? fm.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.intValue ?? 0
        if size > 0, size + data.count > maxBytes {
            let rotated = URL(fileURLWithPath: url.path + ".1")
            try? fm.removeItem(at: rotated)
            try? fm.moveItem(at: url, to: rotated)
        }
        if let handle = try? FileHandle(forWritingTo: url) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
        } else {
            try? data.write(to: url)
        }
    }
}

extension ISO8601DateFormatter {
    static let diagnostics: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        f.timeZone = .current
        return f
    }()
}
