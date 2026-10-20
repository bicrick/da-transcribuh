import Foundation

struct LiveWordUpdate: Equatable {
    var words: [TimedWord]
    var end: TimeInterval
}

enum LiveWordBuffer {
    /// Words that end inside this window stay unconfirmed so the next pass can revise them.
    static let holdback: TimeInterval = 1

    static func appending(
        _ existing: [TimedWord],
        _ incoming: [TimedWord],
        confirmedEnd: TimeInterval
    ) -> LiveWordUpdate {
        var words = existing
        for word in incoming where word.end > word.start && word.start >= confirmedEnd - 0.03 {
            if let last = words.last, last.text == word.text, abs(last.start - word.start) < 0.08 {
                continue
            }
            words.append(word)
        }
        let end = max(confirmedEnd, words.last?.end ?? confirmedEnd)
        return LiveWordUpdate(words: words, end: end)
    }
}
