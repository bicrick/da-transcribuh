import Foundation

/// Quiet stop with nothing to keep: no meaningful speech and no screenshots.
/// Those takes are discarded — not saved to History, not counted in stats /
/// This Week, and they never touch the pasteboard.
enum SessionEmptyTake {
    /// Spoken content after non-speech scrub (whitespace / `[BLANK_AUDIO]` /
    /// `(silence)` / `No speech` annotations become empty).
    static func spokenContent(_ words: [TimedWord]) -> String {
        Aligner.spokenText(words).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// True when the take has no speech worth keeping and no capture tiles.
    /// Transcription failures are not treated as empty — keep those for History.
    static func shouldDiscard(
        words: [TimedWord],
        tileCount: Int,
        transcriptionError: String? = nil
    ) -> Bool {
        if let transcriptionError, !transcriptionError.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return false
        }
        guard tileCount == 0 else { return false }
        return spokenContent(words).isEmpty
    }

    /// Stored folder with no text and no images (incl. orphan dirs without JSON).
    static func shouldPurgeStoredSession(at url: URL, fileManager: FileManager = .default) -> Bool {
        let jsonURL = url.appendingPathComponent("session.json")
        if let data = try? Data(contentsOf: jsonURL),
           let document = try? JSONDecoder().decode(SessionDocument.self, from: data) {
            if let err = document.transcriptionError,
               !err.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return false
            }
            return shouldDiscard(words: document.words, tileCount: document.groups.count)
        }
        return !hasCaptureFrames(at: url, fileManager: fileManager)
    }

    /// Deletes empty stored sessions under `root`. Returns how many folders were removed.
    @discardableResult
    static func purgeEmptySessions(
        in root: URL,
        fileManager: FileManager = .default
    ) -> Int {
        let folders = (try? fileManager.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )) ?? []

        var removed = 0
        for url in folders {
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory),
                  isDirectory.boolValue
            else { continue }
            guard shouldPurgeStoredSession(at: url, fileManager: fileManager) else { continue }
            do {
                try fileManager.removeItem(at: url)
                removed += 1
            } catch {
                ErrorLog.record("Couldn't purge empty session \(url.lastPathComponent): \(error.localizedDescription)")
            }
        }
        return removed
    }

    private static let purgedDefaultsKey = "sessions.purgedEmpty.v1"

    /// One-shot cleanup of empty history folders. Safe to call on every launch;
    /// only walks disk the first time (or when `force` is true).
    @discardableResult
    static func runOneTimeCleanupIfNeeded(
        defaults: UserDefaults = .standard,
        force: Bool = false
    ) -> Int {
        guard force || !defaults.bool(forKey: purgedDefaultsKey) else { return 0 }
        defer { defaults.set(true, forKey: purgedDefaultsKey) }
        guard let root = try? SessionPaths.sessionsRoot() else { return 0 }
        let removed = purgeEmptySessions(in: root)
        if removed > 0 {
            NotificationCenter.default.post(name: .promptAnnotatorSessionsChanged, object: nil)
        }
        return removed
    }

    private static func hasCaptureFrames(at url: URL, fileManager: FileManager) -> Bool {
        let frames = url.appendingPathComponent("frames", isDirectory: true)
        guard let items = try? fileManager.contentsOfDirectory(
            at: frames,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else { return false }
        return items.contains { $0.pathExtension.lowercased() == "png" }
    }
}
