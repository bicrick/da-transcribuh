import Foundation

struct TimedWord: Codable, Equatable, Sendable {
    var text: String
    var start: TimeInterval
    var end: TimeInterval
}

/// Assigns word timings to Shift-commit groups.
///
/// A word belongs to the group whose commit interval contains the word's start.
/// The first interval begins at the start of the session. The end of an interval
/// is inclusive, so a word that starts on the commit instant stays with that tile.
/// Words that start after the last commit and at or before the session end are
/// the closing note on the last group. Commit times are in session order and
/// must be non-decreasing.
enum Aligner {
    struct Group: Equatable {
        var words: [TimedWord]
        var closingNote: [TimedWord]
    }

    static func align(
        words: [TimedWord],
        commitTimes: [TimeInterval],
        sessionEnd: TimeInterval
    ) -> [Group] {
        guard !commitTimes.isEmpty else { return [] }

        let sorted = words.sorted { lhs, rhs in
            if lhs.start == rhs.start { return lhs.end < rhs.end }
            return lhs.start < rhs.start
        }

        var groups = Array(repeating: Group(words: [], closingNote: []), count: commitTimes.count)
        var previous = -TimeInterval.infinity
        let endLimit = sessionEnd + 0.001

        for (index, commit) in commitTimes.enumerated() {
            groups[index].words = sorted.filter { word in
                word.start > previous && word.start <= commit && word.start <= endLimit
            }
            previous = commit
        }

        if let lastCommit = commitTimes.last {
            let closing = sorted.filter { word in
                word.start > lastCommit && word.start <= sessionEnd + 0.05
            }
            groups[groups.count - 1].closingNote = closing
        }

        return groups
    }

    static func spokenText(_ words: [TimedWord]) -> String {
        let joined = NonSpeechFilter.filterWords(words)
            .map { $0.text.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        return NonSpeechFilter.scrub(joined)
    }
}
