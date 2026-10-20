import Foundation

@MainActor
enum ErrorLog {
    static func record(_ message: String) {
        guard AppSettings.shared.errorLogging else { return }
        let line = "\(Stamp.iso.string(from: Date())) \(message)\n"
        let url = fileURL()
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let data = line.data(using: .utf8) {
            if FileManager.default.fileExists(atPath: url.path),
               let handle = try? FileHandle(forWritingTo: url) {
                defer { try? handle.close() }
                _ = try? handle.seekToEnd()
                try? handle.write(contentsOf: data)
            } else {
                try? data.write(to: url)
            }
        }
    }

    static func fileURL() -> URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return support.appendingPathComponent("PromptAnnotator/errors.log")
    }
}
