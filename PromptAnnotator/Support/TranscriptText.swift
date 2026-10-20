import Foundation

enum TranscriptText {
    /// Capitalizes the first letter, leaving a leading number such as `1.` in place.
    static func leadingCapital(_ text: String) -> String {
        guard let index = text.firstIndex(where: { $0.isLetter }) else { return text }
        var copy = text
        copy.replaceSubrange(index...index, with: String(copy[index]).uppercased())
        return copy
    }
}
