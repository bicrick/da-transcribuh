import Foundation

struct SessionSummary: Identifiable, Equatable {
    var id: String
    var url: URL
    var started: Date?
    var ended: Date?
    var tiles: Int
    var words: Int
    var model: String?
    var transcript: String
    var preview: String

    var duration: TimeInterval {
        guard let started, let ended else { return 0 }
        return max(0, ended.timeIntervalSince(started))
    }
}

struct SessionStats: Equatable {
    var sessions: Int
    var tiles: Int
    var words: Int
    var minutes: Int

    static let empty = SessionStats(sessions: 0, tiles: 0, words: 0, minutes: 0)
}

enum SessionLibrary {
    static func load() -> [SessionSummary] {
        guard let root = try? SessionPaths.sessionsRoot() else { return [] }
        return summaries(in: root)
    }

    static func summaries(in root: URL) -> [SessionSummary] {
        let keys: [URLResourceKey] = [.isDirectoryKey]
        let folders = (try? FileManager.default.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles]
        )) ?? []

        let dirs = folders.filter {
            (try? $0.resourceValues(forKeys: Set(keys)).isDirectory) == true
        }
        return summaryCache.summaries(for: dirs) { url in summary(at: url) }
            .sorted { lhs, rhs in
                (lhs.started ?? .distantPast) > (rhs.started ?? .distantPast)
            }
    }

    /// Settings reloads on every show and every finished take. Re-decoding every
    /// session.json each time cost ~0.45 ms per session on the main thread
    /// (191 ms at 430 sessions, run twice on first open). Only folders whose
    /// session.json changed (mtime or size) are decoded again.
    static let summaryCache = SummaryCache()

    final class SummaryCache: @unchecked Sendable {
        private struct Entry {
            var stamp: FileStamp
            var summary: SessionSummary
        }

        private struct FileStamp: Equatable {
            var modified: Date?
            var size: Int?
        }

        private let lock = NSLock()
        private var entries: [String: Entry] = [:]

        func summaries(for dirs: [URL], decode: (URL) -> SessionSummary) -> [SessionSummary] {
            let stamped = dirs.map { url -> (URL, FileStamp) in
                let json = url.appendingPathComponent("session.json")
                let values = try? json.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
                return (url, FileStamp(modified: values?.contentModificationDate, size: values?.fileSize))
            }
            lock.lock()
            let known = entries
            lock.unlock()

            var next: [String: Entry] = [:]
            next.reserveCapacity(stamped.count)
            var result: [SessionSummary] = []
            result.reserveCapacity(stamped.count)
            for (url, stamp) in stamped {
                let key = url.standardizedFileURL.path
                if let hit = known[key], hit.stamp == stamp, hit.stamp.modified != nil {
                    next[key] = hit
                    result.append(hit.summary)
                } else {
                    let summary = decode(url)
                    next[key] = Entry(stamp: stamp, summary: summary)
                    result.append(summary)
                }
            }
            lock.lock()
            entries = next
            lock.unlock()
            return result
        }

        func removeAll() {
            lock.lock()
            entries.removeAll()
            lock.unlock()
        }
    }

    static func stats(from sessions: [SessionSummary]) -> SessionStats {
        let seconds = sessions.reduce(0) { $0 + $1.duration }
        return SessionStats(
            sessions: sessions.count,
            tiles: sessions.reduce(0) { $0 + $1.tiles },
            words: sessions.reduce(0) { $0 + $1.words },
            minutes: Int((seconds / 60).rounded())
        )
    }

    private static func summary(at url: URL) -> SessionSummary {
        let jsonURL = url.appendingPathComponent("session.json")
        if let data = try? Data(contentsOf: jsonURL),
           let document = try? JSONDecoder().decode(SessionDocument.self, from: data) {
            let words = document.words.filter {
                !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }
            let transcript = Aligner.spokenText(words)
            return SessionSummary(
                id: url.lastPathComponent,
                url: url,
                started: Stamp.iso.date(from: document.startedAt),
                ended: Stamp.iso.date(from: document.endedAt),
                tiles: document.groups.count,
                words: words.count,
                model: document.model,
                transcript: transcript,
                preview: SessionLibrary.preview(transcript)
            )
        }

        return SessionSummary(
            id: url.lastPathComponent,
            url: url,
            started: Stamp.folder.date(from: url.lastPathComponent),
            ended: nil,
            tiles: 0,
            words: 0,
            model: nil,
            transcript: "",
            preview: ""
        )
    }

    static func preview(_ transcript: String) -> String {
        let line = transcript.split(whereSeparator: \.isNewline).first.map(String.init) ?? transcript
        if line.count <= 90 { return line }
        return String(line.prefix(89)) + "..."
    }

    /// Newest-first slice for Home RECENT (same sort as `load()` / History).
    static func recent(_ sessions: [SessionSummary], limit: Int = 4) -> [SessionSummary] {
        Array(sessions.prefix(max(0, limit)))
    }

    /// Words spoken on each of the last 7 calendar days (index 0 = six days ago, 6 = today).
    static func weeklyWordCounts(
        from sessions: [SessionSummary],
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> [Int] {
        let today = calendar.startOfDay(for: now)
        guard let start = calendar.date(byAdding: .day, value: -6, to: today) else {
            return Array(repeating: 0, count: 7)
        }
        var counts = Array(repeating: 0, count: 7)
        for session in sessions {
            guard let started = session.started else { continue }
            let day = calendar.startOfDay(for: started)
            guard day >= start, day <= today else { continue }
            let offset = calendar.dateComponents([.day], from: start, to: day).day ?? -1
            guard offset >= 0, offset < 7 else { continue }
            counts[offset] += session.words
        }
        return counts
    }

    /// Relative label for RECENT rows: `11:42` today, weekday if this week, else a short date.
    static func recentWhen(
        _ date: Date?,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> String {
        guard let date else { return "—" }
        let today = calendar.startOfDay(for: now)
        let day = calendar.startOfDay(for: date)
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        if calendar.isDate(date, inSameDayAs: now) {
            formatter.dateFormat = "H:mm"
            return formatter.string(from: date)
        }
        if let weekAgo = calendar.date(byAdding: .day, value: -6, to: today), day >= weekAgo {
            formatter.dateFormat = "EEE"
            return formatter.string(from: date)
        }
        formatter.dateFormat = "MMM d"
        return formatter.string(from: date)
    }

    /// Contact-sheet thumbnail when the session has captures.
    static func thumbnailURL(for session: SessionSummary) -> URL? {
        guard session.tiles > 0 else { return nil }
        let sheet = session.url.appendingPathComponent("sheet.png")
        if FileManager.default.fileExists(atPath: sheet.path) { return sheet }
        let frame = session.url.appendingPathComponent("frames/01.png")
        if FileManager.default.fileExists(atPath: frame.path) { return frame }
        return nil
    }
}
