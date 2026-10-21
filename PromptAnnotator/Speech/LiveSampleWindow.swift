import Foundation

/// Bounds how much PCM is sent to a live Whisper decode.
/// Confirmed words already sit in `LiveWordBuffer`; only a short overlapping tail is re-decoded.
enum LiveSampleWindow {
    /// Hard cap on samples passed into one live decode (~45 s @ 16 kHz).
    static let maxSeconds: TimeInterval = 45
    /// Keep a little audio before `clipStart` so a word straddling the boundary can revise.
    static let overlap: TimeInterval = 0.35

    struct Slice: Equatable {
        /// PCM starting at `timeOffset` (session-absolute seconds).
        var samples: [Float]
        var timeOffset: TimeInterval
    }

    /// Picks a decode window from a (possibly already-trimmed) speech buffer.
    /// - Parameters:
    ///   - samples: Buffer whose index 0 is `bufferStart` seconds into the session.
    ///   - bufferStart: Absolute time of `samples[0]`.
    ///   - clipStart: Absolute time already confirmed; decode may start just before this.
    ///   - sampleRate: Whisper PCM rate (16 kHz).
    static func slice(
        samples: [Float],
        bufferStart: TimeInterval,
        clipStart: TimeInterval,
        sampleRate: Int
    ) -> Slice {
        guard !samples.isEmpty, sampleRate > 0 else {
            return Slice(samples: [], timeOffset: bufferStart)
        }
        let rate = Double(sampleRate)
        let bufferEnd = bufferStart + Double(samples.count) / rate

        var absStart = bufferStart
        if clipStart > 0.05 {
            absStart = max(bufferStart, clipStart - overlap)
        }
        if bufferEnd - absStart > maxSeconds {
            absStart = max(absStart, bufferEnd - maxSeconds)
        }

        let local = Int(((absStart - bufferStart) * rate).rounded(.down))
        let startIndex = min(samples.count, max(0, local))
        if startIndex == 0 {
            return Slice(samples: samples, timeOffset: bufferStart)
        }
        let offset = bufferStart + Double(startIndex) / rate
        return Slice(samples: Array(samples[startIndex...]), timeOffset: offset)
    }
}
