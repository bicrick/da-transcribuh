import CoreGraphics
import Foundation

/// Live frequency bars. Each slot keeps its pitch, from low on the left to high on the right.
enum FrequencyBands {
    static let window = 512
    static let sampleRate = 16_000.0

    static func levels(samples: [Float], count: Int) -> [CGFloat] {
        guard count > 0 else { return [] }
        let frame = Array(samples.suffix(window))
        guard frame.count >= 128, rms(frame) > 0.008 else { return rest(count) }

        let n = frame.count
        var magnitudes = [Double](repeating: 0, count: count)
        for band in 0..<count {
            let hz = frequency(band: band, count: count)
            let omega = 2 * Double.pi * hz / sampleRate
            var real = 0.0
            var imag = 0.0
            for index in 0..<n {
                let hann = 0.5 * (1 - cos(2 * Double.pi * Double(index) / Double(n - 1)))
                let sample = Double(frame[index]) * hann
                let angle = omega * Double(index)
                real += sample * cos(angle)
                imag -= sample * sin(angle)
            }
            magnitudes[band] = sqrt(real * real + imag * imag) / Double(n)
        }

        return magnitudes.map { magnitude in
            let decibels = 20 * log10(max(magnitude, 1e-8))
            let scaled = (decibels + 62) / 42
            return CGFloat(min(1, max(0.08, scaled)))
        }
    }

    static func shaped(level: CGFloat, count: Int) -> [CGFloat] {
        guard count > 0 else { return [] }
        return (0..<count).map { index in
            let position = Double(index) / Double(max(count - 1, 1))
            let envelope = 1 - abs(position - 0.5) * 1.15
            let height = 0.08 + (Double(level) * 0.9 * max(0.25, envelope))
            return CGFloat(min(1, max(0.08, height)))
        }
    }

    static func smooth(_ current: [CGFloat], toward target: [CGFloat]) -> [CGFloat] {
        let count = max(current.count, target.count)
        return (0..<count).map { index in
            let from = index < current.count ? current[index] : 0.12
            let to = index < target.count ? target[index] : 0.12
            let rate: CGFloat = to > from ? 0.72 : 0.34
            return from + (to - from) * rate
        }
    }

    static func frequency(band: Int, count: Int) -> Double {
        let span = Double(band) / Double(max(count - 1, 1))
        return 100 * pow(34, span)
    }

    static func resting(_ count: Int) -> [CGFloat] {
        rest(count)
    }

    private static func rest(_ count: Int) -> [CGFloat] {
        (0..<count).map { index in
            let position = Double(index) / Double(max(count - 1, 1))
            let center = max(0, 1 - abs(position - 0.5) * 2)
            return CGFloat(0.08 + 0.05 * center)
        }
    }

    private static func rms(_ samples: [Float]) -> Float {
        var sum: Float = 0
        for sample in samples {
            sum += sample * sample
        }
        return sqrt(sum / Float(samples.count))
    }
}
