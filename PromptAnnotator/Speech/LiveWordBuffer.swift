import Foundation

struct LiveWordUpdate: Equatable {
    var words: [TimedWord]
    var end: TimeInterval
}

enum LiveWordBuffer {
    /// Words that end inside this window stay unconfirmed so the next pass can revise them.
    static let holdback: TimeInterval = 1

    /// A word re-emitted at a decode seam starts within this gap after the confirmed word it
    /// echoes. Measured seam echoes ("and and", "the the", "make make") restart 0 to 0.4 s after
    /// the confirmed word ends, with re-decoded timestamps that no longer match the original,
    /// so the old 0.08 s start-time check never caught them.
    static let echoGap: TimeInterval = 0.5

    static func appending(
        _ existing: [TimedWord],
        _ incoming: [TimedWord],
        confirmedEnd: TimeInterval
    ) -> LiveWordUpdate {
        var fresh = incoming.filter { $0.end > $0.start && $0.start >= confirmedEnd - 0.03 }
        fresh = dropSeamEcho(existing: existing, fresh: fresh)
        let words = existing + fresh
        let end = max(confirmedEnd, words.last?.end ?? confirmedEnd)
        return LiveWordUpdate(words: words, end: end)
    }

    /// Drops the first one or two incoming words when they repeat the last confirmed words
    /// right at the seam. Only the seam is touched; a repeat later in the decode is the
    /// speaker's, not ours.
    static func dropSeamEcho(existing: [TimedWord], fresh: [TimedWord]) -> [TimedWord] {
        guard let last = existing.last, let first = fresh.first else { return fresh }
        guard first.start - last.end < echoGap else { return fresh }
        if existing.count >= 2, fresh.count >= 2,
           key(existing[existing.count - 2].text) == key(first.text),
           key(last.text) == key(fresh[1].text), !key(first.text).isEmpty {
            return Array(fresh.dropFirst(2))
        }
        if key(last.text) == key(first.text), !key(first.text).isEmpty {
            return Array(fresh.dropFirst())
        }
        return fresh
    }

    /// Case- and punctuation-insensitive word key.
    static func key(_ text: String) -> String {
        String(text.lowercased().unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }.map(Character.init))
    }
}
