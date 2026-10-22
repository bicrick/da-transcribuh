import Foundation

/// Turns technical failures into short menu- and alert-safe copy.
enum UserFacingError {
    static func sessionStart(_ error: Error) -> String {
        if let export = error as? ExportError { return export.message }
        return trimmed(error.localizedDescription) ?? "Couldn't start the session."
    }

    static func sessionWrite(_ error: Error) -> String {
        if let export = error as? ExportError { return export.message }
        return trimmed(error.localizedDescription) ?? "Couldn't save the session."
    }

    static func transcription(_ error: Error) -> String {
        let raw = error.localizedDescription
        let lower = raw.lowercased()
        if lower.contains("cancel") {
            return "Transcription was cancelled."
        }
        if isNetworkFailure(lower) {
            return "Couldn't download the speech model. Check the network and try again."
        }
        if isDiskFull(lower) {
            return "Couldn't save the speech model. Free some disk space and try again."
        }
        if lower.contains("model") && (lower.contains("not found") || lower.contains("missing") || lower.contains("exist")) {
            return "The speech model is missing. Open Model settings to download it."
        }
        if raw.contains("Error Domain") || raw.count > 140 {
            return "Transcription failed. Try another session, or check the error log in Configuration."
        }
        return trimmed(raw) ?? "Transcription failed."
    }

    /// Model picker / onboarding download failures — never dump `Error Domain=…`.
    static func modelDownload(_ error: Error) -> String {
        let raw = error.localizedDescription
        let lower = raw.lowercased()
        if lower.contains("cancel") {
            return "Download was cancelled."
        }
        if isNetworkFailure(lower) {
            return "Couldn't download the speech model. Check the network and try again."
        }
        if isDiskFull(lower) {
            return "Couldn't save the speech model. Free some disk space and try again."
        }
        if raw.contains("Error Domain") || raw.count > 140 {
            return "Couldn't download the speech model. Check the network and try again."
        }
        return trimmed(raw) ?? "Couldn't download the speech model."
    }

    static func capture(_ error: Error) -> String {
        if let export = error as? ExportError { return export.message }
        return trimmed(error.localizedDescription) ?? "Couldn't capture the screen."
    }

    private static func isNetworkFailure(_ lower: String) -> Bool {
        lower.contains("network") || lower.contains("offline") || lower.contains("internet")
            || lower.contains("timed out") || lower.contains("timeout")
    }

    private static func isDiskFull(_ lower: String) -> Bool {
        lower.contains("no space") || lower.contains("disk full") || lower.contains("not enough disk")
    }

    private static func trimmed(_ text: String) -> String? {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}
