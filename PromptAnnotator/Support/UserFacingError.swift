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
        if lower.contains("network") || lower.contains("offline") || lower.contains("internet")
            || lower.contains("timed out") || lower.contains("timeout") {
            return "Couldn't download the speech model. Check the network and try again."
        }
        if lower.contains("no space") || lower.contains("disk full") || lower.contains("not enough disk") {
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

    static func capture(_ error: Error) -> String {
        if let export = error as? ExportError { return export.message }
        return trimmed(error.localizedDescription) ?? "Couldn't capture the screen."
    }

    private static func trimmed(_ text: String) -> String? {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}
