import Foundation

struct SessionSummary: Identifiable, Equatable {
    var id: String
    var url: URL
    var started: Date?
    var ended: Date?
    var tiles: Int
    var words: Int
    var model: String?

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
        let folders = (try? FileManager.default.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )) ?? []

        return folders.compactMap { url in
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue else {
                return nil
            }
            return summary(at: url)
        }
        .sorted { lhs, rhs in
            (lhs.started ?? .distantPast) > (rhs.started ?? .distantPast)
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
            return SessionSummary(
                id: url.lastPathComponent,
                url: url,
                started: Stamp.iso.date(from: document.startedAt),
                ended: Stamp.iso.date(from: document.endedAt),
                tiles: document.groups.count,
                words: words.count,
                model: document.model
            )
        }

        return SessionSummary(
            id: url.lastPathComponent,
            url: url,
            started: Stamp.folder.date(from: url.lastPathComponent),
            ended: nil,
            tiles: 0,
            words: 0,
            model: nil
        )
    }
}
