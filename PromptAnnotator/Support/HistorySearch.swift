import Foundation

enum HistorySearch {
    static func filter(_ sessions: [SessionSummary], query: String) -> [SessionSummary] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return sessions }
        return sessions.filter { session in
            session.transcript.localizedCaseInsensitiveContains(needle)
                || session.preview.localizedCaseInsensitiveContains(needle)
                || session.id.localizedCaseInsensitiveContains(needle)
                || (session.model ?? "").localizedCaseInsensitiveContains(needle)
        }
    }
}
