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

    struct Match: Equatable {
        var score: Int
        var snippet: String
        /// UTF-16 NSRange into `snippet` for the matched needle.
        var range: NSRange
    }

    /// Best transcript/preview match with a paint-yellow-ready snippet.
    static func firstMatch(in session: SessionSummary, query: String) -> Match? {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return nil }

        let fields: [(String, Int)] = [
            (session.transcript, 80),
            (session.preview, 60),
            (session.id, 30),
            (session.model ?? "", 20),
        ]
        var best: Match?
        for (field, base) in fields {
            guard let range = field.range(of: needle, options: [.caseInsensitive, .diacriticInsensitive]) else {
                continue
            }
            let snippet = makeSnippet(in: field, match: range, radius: 42)
            guard let local = snippet.range(of: needle, options: [.caseInsensitive, .diacriticInsensitive]) else {
                continue
            }
            let ns = NSRange(local, in: snippet)
            let prefixBonus = field.lowercased().hasPrefix(needle.lowercased()) ? 20 : 0
            let candidate = Match(score: base + prefixBonus, snippet: snippet, range: ns)
            if best == nil || candidate.score > best!.score {
                best = candidate
            }
        }
        return best
    }

    static func makeSnippet(in text: String, match: Range<String.Index>, radius: Int) -> String {
        let start = text.index(match.lowerBound, offsetBy: -radius, limitedBy: text.startIndex) ?? text.startIndex
        let end = text.index(match.upperBound, offsetBy: radius, limitedBy: text.endIndex) ?? text.endIndex
        var snippet = String(text[start..<end])
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if start > text.startIndex { snippet = "…" + snippet }
        if end < text.endIndex { snippet = snippet + "…" }
        return snippet
    }
}
