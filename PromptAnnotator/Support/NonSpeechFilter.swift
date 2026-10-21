import Foundation

/// Strips Whisper non-speech captions such as `[BLANK_AUDIO]`, `(silence)`, and `[Music]`
/// from timed words and joined transcript text. Real spoken parentheticals that are not
/// sound or silence labels are left alone.
enum NonSpeechFilter {
    /// Exact labels (normalized) Whisper commonly emits for non-speech audio.
    private static let labels: Set<String> = [
        "silence",
        "blank audio",
        "blankaudio",
        "music",
        "applause",
        "laughter",
        "laughing",
        "laughs",
        "laugh",
        "coughing",
        "cough",
        "coughs",
        "sneezing",
        "sneeze",
        "sniffling",
        "sniffle",
        "typing",
        "keyboard",
        "keyboard clacking",
        "clacking",
        "clicking",
        "click",
        "clicks",
        "mouse clicking",
        "rustling",
        "static",
        "noise",
        "background noise",
        "white noise",
        "inaudible",
        "indistinct",
        "unintelligible",
        "speaking in foreign language",
        "foreign language",
        "non english speech",
        "music playing",
        "door slamming",
        "beep",
        "beeping",
        "ringing",
        "phone ringing",
        "alarm",
        "crying",
        "sobbing",
        "sighing",
        "sigh",
        "breathing",
        "exhales",
        "inhales",
        "whistling",
        "humming",
        "singing",
        "crowd",
        "cheering",
        "chatter",
        "audience",
        "buzzing",
        "hum",
        "drums",
        "guitar",
        "piano",
        "song",
        "theme music",
        "intro music",
        "outro music",
        "no speech",
        "nospeech",
        "empty",
        "blank",
    ]

    /// True when `text` is only a non-speech annotation (with or without brackets/parens).
    static func isAnnotationToken(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        if isMusicGlyph(trimmed) { return true }
        if let wrapped = fullyWrappedContent(trimmed) {
            return isAnnotationContent(wrapped)
        }
        return isBareAnnotationToken(trimmed)
    }

    /// Drops annotation words, including split forms like `(`, `silence`, `)`.
    static func filterWords(_ words: [TimedWord]) -> [TimedWord] {
        guard !words.isEmpty else { return words }
        var kept: [TimedWord] = []
        var index = 0
        while index < words.count {
            let raw = words[index].text
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)

            if isAnnotationToken(trimmed) {
                index += 1
                continue
            }

            if let open = opener(trimmed),
               let closeIndex = closingIndex(in: words, from: index, open: open) {
                let innerWords = words[(index + 1)..<closeIndex]
                let inner = innerWords
                    .map { $0.text.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
                    .joined(separator: " ")
                if isAnnotationContent(inner) {
                    index = closeIndex + 1
                    continue
                }
            }

            kept.append(words[index])
            index += 1
        }
        return kept
    }

    /// Removes annotation spans from joined transcript text and collapses leftover spaces.
    static func scrub(_ text: String) -> String {
        guard !text.isEmpty else { return text }
        var result = text
        result = scrubWrappedSpans(result, open: "[", close: "]")
        result = scrubWrappedSpans(result, open: "(", close: ")")
        result = scrubBareLabels(result)
        result = result.replacingOccurrences(of: #"[\u{266A}\u{266B}\u{266C}\u{266D}]+"#, with: " ", options: .regularExpression)
        return collapseWhitespace(result)
    }

    // MARK: - Content checks

    static func isAnnotationContent(_ raw: String) -> Bool {
        let normalized = normalize(raw)
        guard !normalized.isEmpty else { return true }
        if labels.contains(normalized) { return true }
        if normalized.contains("blank") && normalized.contains("audio") { return true }
        if normalized.hasPrefix("blank audio") { return true }
        if normalized.contains("clack") { return true }
        if normalized.contains("keyboard") && (normalized.contains("type") || normalized.contains("click") || normalized.contains("clack")) {
            return true
        }
        if normalized == "music" || normalized.hasPrefix("music ") || normalized.hasSuffix(" music") {
            return true
        }
        if isMusicGlyph(normalized) { return true }
        // ALL_CAPS_SNAKE sound tags Whisper sometimes emits without brackets.
        if isCapsSnakeSoundTag(raw.trimmingCharacters(in: .whitespacesAndNewlines)) {
            return true
        }
        return false
    }

    /// Unwrapped tokens are only dropped when they look like model tags (`BLANK_AUDIO`),
    /// not when someone says the word "silence" or "music" out loud.
    private static func isBareAnnotationToken(_ trimmed: String) -> Bool {
        if isCapsSnakeSoundTag(trimmed) { return true }
        let normalized = normalize(trimmed)
        return normalized.contains("blank") && normalized.contains("audio")
    }

    private static func isCapsSnakeSoundTag(_ text: String) -> Bool {
        guard text.count >= 4, text.contains("_") else { return false }
        let allowed = CharacterSet.uppercaseLetters.union(CharacterSet(charactersIn: "_"))
        return text.unicodeScalars.allSatisfy { allowed.contains($0) }
    }

    private static func isMusicGlyph(_ text: String) -> Bool {
        let glyphs = CharacterSet(charactersIn: "♪♫♬♩")
        return !text.isEmpty && text.unicodeScalars.allSatisfy { glyphs.contains($0) }
    }

    static func normalize(_ raw: String) -> String {
        let lowered = raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: ".", with: "")
            .replacingOccurrences(of: ",", with: "")
        return collapseWhitespace(lowered)
    }

    // MARK: - Wrappers

    private enum Wrapper {
        case bracket
        case paren
    }

    private static func opener(_ text: String) -> Wrapper? {
        if text == "[" { return .bracket }
        if text == "(" { return .paren }
        return nil
    }

    private static func closingIndex(in words: [TimedWord], from start: Int, open: Wrapper) -> Int? {
        let close: String = open == .bracket ? "]" : ")"
        var depth = 0
        for index in start..<words.count {
            let token = words[index].text.trimmingCharacters(in: .whitespacesAndNewlines)
            if token == (open == .bracket ? "[" : "(") || (index == start && (token == "[" || token == "(")) {
                depth += 1
                continue
            }
            if token == close {
                depth -= 1
                if depth == 0 { return index }
            }
        }
        return nil
    }

    private static func fullyWrappedContent(_ text: String) -> String? {
        guard text.count >= 2 else { return nil }
        if text.hasPrefix("["), text.hasSuffix("]") {
            return String(text.dropFirst().dropLast())
        }
        if text.hasPrefix("("), text.hasSuffix(")") {
            return String(text.dropFirst().dropLast())
        }
        return nil
    }

    private static func scrubWrappedSpans(_ text: String, open: String, close: String) -> String {
        var output = ""
        var index = text.startIndex
        while index < text.endIndex {
            if text[index...].hasPrefix(open),
               let closeRange = text.range(of: close, range: text.index(after: index)..<text.endIndex) {
                let innerStart = text.index(after: index)
                let inner = String(text[innerStart..<closeRange.lowerBound])
                if isAnnotationContent(inner) {
                    index = closeRange.upperBound
                    continue
                }
            }
            output.append(text[index])
            index = text.index(after: index)
        }
        return output
    }

    private static func scrubBareLabels(_ text: String) -> String {
        // Whole-string blank audio tags that survived without wrappers.
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if isAnnotationToken(trimmed) { return "" }
        var result = text
        let patterns = [
            #"\bBLANK_AUDIO\b"#,
            #"\bNO_SPEECH\b"#,
        ]
        for pattern in patterns {
            result = result.replacingOccurrences(of: pattern, with: " ", options: [.regularExpression, .caseInsensitive])
        }
        return result
    }

    private static func collapseWhitespace(_ text: String) -> String {
        let parts = text
            .split(whereSeparator: { $0.isWhitespace })
            .map(String.init)
        return parts.joined(separator: " ")
    }
}
