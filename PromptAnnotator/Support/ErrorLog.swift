import Foundation

@MainActor
enum ErrorLog {
    /// errors.log rotates into errors.log.1 past this size, so it can no longer grow without bound.
    static let maxBytes = 256 * 1024

    static func record(_ message: String) {
        // The diagnostics log always gets the event; errors.log stays opt-in.
        AppLog.error(message)
        guard AppSettings.shared.errorLogging else { return }
        let line = "\(Stamp.iso.string(from: Date())) \(message)\n"
        AppLog.append(line, to: fileURL(), maxBytes: maxBytes)
    }

    static func fileURL() -> URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return support.appendingPathComponent("PromptAnnotator/errors.log")
    }
}
