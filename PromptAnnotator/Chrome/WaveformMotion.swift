import CoreGraphics

/// Bars that pulse where they stand while a spoken session is being finished.
enum WaveformMotion {
    static func loading(frame: Int, count: Int = WaveformSamples.count) -> [CGFloat] {
        (0..<count).map { index in
            let position = Double(index) / Double(max(count - 1, 1))
            let center = 1 - abs(position - 0.5) * 0.35
            let pulse = sin(Double(frame) * 0.22 + Double(index) * 0.85)
            let level = 0.16 + (pulse * 0.5 + 0.5) * 0.62 * center
            return CGFloat(min(1, max(0.08, level)))
        }
    }
}
