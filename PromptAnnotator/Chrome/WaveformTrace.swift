import CoreGraphics

/// A short scrolling waveform. New sound enters on the right, the way a voice trace does.
enum WaveformTrace {
    static let columns = 180
    static let windowSeconds = 2.4
    static let sampleRate = 16_000.0
    /// Quiet columns stay a hairline so the bar reads as a dotted baseline.
    static let floor: CGFloat = 0.05

    static var windowSamples: Int {
        Int(windowSeconds * sampleRate)
    }

    static func resting(count: Int = columns) -> [CGFloat] {
        Array(repeating: floor, count: max(0, count))
    }

    static func levels(samples: [Float], columns: Int = columns) -> [CGFloat] {
        guard columns > 0 else { return [] }
        let capacity = max(columns, windowSamples)
        let frame = samples.suffix(capacity)
        guard !frame.isEmpty else { return resting(count: columns) }

        var peaks = [Float](repeating: 0, count: columns)
        let offset = capacity - frame.count
        let span = Double(capacity) / Double(columns)
        for (index, sample) in frame.enumerated() {
            let column = min(columns - 1, Int(Double(offset + index) / span))
            let magnitude = abs(sample)
            if magnitude > peaks[column] {
                peaks[column] = magnitude
            }
        }
        return peaks.map(shaped)
    }

    static func shaped(_ peak: Float) -> CGFloat {
        let clamped = min(1, max(0, peak))
        if clamped < 0.012 { return floor }
        let curved = pow(Double(clamped), 0.62)
        return CGFloat(min(1, max(Double(floor), curved * 1.45)))
    }

    /// Meter fallback is already scaled from 0 to 1.
    static func fromMeter(_ level: CGFloat) -> CGFloat {
        let clamped = min(1, max(0, level))
        if clamped < 0.08 { return floor }
        return clamped
    }
}
