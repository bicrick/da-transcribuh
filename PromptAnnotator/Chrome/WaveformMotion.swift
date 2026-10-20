import CoreGraphics

/// A traveling ripple used while a spoken session is being finished.
enum WaveformMotion {
    static func loading(frame: Int, count: Int = WaveformSamples.count) -> [CGFloat] {
        let travel = Double(frame) * 0.38
        return (0..<count).map { index in
            let position = Double(index) / Double(max(count - 1, 1))
            let ripple = sin(position * .pi * 3 + travel)
            let breathe = sin(travel * 0.45)
            let level = 0.2 + 0.22 * (breathe * 0.5 + 0.5) + 0.45 * (ripple * 0.5 + 0.5)
            return CGFloat(min(1, max(0.08, level)))
        }
    }
}
