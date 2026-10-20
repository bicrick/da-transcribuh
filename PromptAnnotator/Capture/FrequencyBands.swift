import Accelerate
import CoreGraphics
import Foundation

/// Live frequency bars. Each slot keeps its pitch, from low on the left to high on the right.
/// Only the height changes. The bar does not scroll.
enum FrequencyBands {
    static let window = 1024
    static let sampleRate = 16_000.0

    static func levels(samples: [Float], count: Int) -> [CGFloat] {
        guard count > 0 else { return [] }
        let frame = Array(samples.suffix(window))
        // Only a dead buffer collapses to the rest shape. A hard loudness gate
        // made quiet speech and the gaps between syllables flash the whole comb.
        guard frame.count >= 128, rms(frame) > 0.0008 else { return rest(count) }
        guard let magnitudes = spectrum(frame) else { return rest(count) }
        let raw = (0..<count).map { band in
            height(for: bandEnergy(magnitudes, band: band, count: count))
        }
        return soften(raw)
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

    /// Eases each slot toward its new height. Rising is quicker than falling, and nothing changes place.
    /// `delta` is seconds since the last frame, so the motion stays the same if the display skips.
    static func smooth(_ current: [CGFloat], toward target: [CGFloat], delta: TimeInterval = 0.02) -> [CGFloat] {
        let step = max(0, delta)
        let attack = CGFloat(1 - exp(-step / 0.028))
        let release = CGFloat(1 - exp(-step / 0.18))
        let count = max(current.count, target.count)
        return (0..<count).map { index in
            let from = index < current.count ? current[index] : 0.1
            let to = index < target.count ? target[index] : 0.1
            let rate: CGFloat = to > from ? attack : release
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

    /// A full-scale sine lands near −7 dB with this FFT. The knee is low enough that
    /// quiet speech leaves the floor, and a pure tone's distant bins stay there.
    private static func height(for energy: Float) -> CGFloat {
        let decibels = 20 * log10(max(energy, 1e-8))
        let normalized = min(1, max(0, (decibels + 72) / 46))
        let curved = pow(normalized, 0.85)
        return CGFloat(min(1, 0.08 + curved * 0.92))
    }

    /// Shares a little of each bar with its neighbors so a single bin doesn't spike alone.
    private static func soften(_ levels: [CGFloat]) -> [CGFloat] {
        guard levels.count > 2 else { return levels }
        return levels.indices.map { index in
            let left = levels[max(0, index - 1)]
            let right = levels[min(levels.count - 1, index + 1)]
            return left * 0.22 + levels[index] * 0.56 + right * 0.22
        }
    }

    private static func rms(_ samples: [Float]) -> Float {
        var sum: Float = 0
        vDSP_svesq(samples, 1, &sum, vDSP_Length(samples.count))
        return sqrt(sum / Float(samples.count))
    }

    /// One real FFT. Bin width is `sampleRate / window`.
    private static func spectrum(_ frame: [Float]) -> [Float]? {
        let n = window
        let log2n = vDSP_Length(10)
        guard let setup = FFTCache.setup else { return nil }

        var buffer = [Float](repeating: 0, count: n)
        let copyCount = min(n, frame.count)
        for index in 0..<copyCount {
            buffer[index] = frame[frame.count - copyCount + index]
        }
        var hann = [Float](repeating: 0, count: n)
        vDSP_hann_window(&hann, vDSP_Length(n), Int32(vDSP_HANN_NORM))
        vDSP_vmul(buffer, 1, hann, 1, &buffer, 1, vDSP_Length(n))

        var real = [Float](repeating: 0, count: n / 2)
        var imag = [Float](repeating: 0, count: n / 2)
        var magnitudes = [Float](repeating: 0, count: n / 2)
        real.withUnsafeMutableBufferPointer { realPtr in
            imag.withUnsafeMutableBufferPointer { imagPtr in
                guard let realBase = realPtr.baseAddress, let imagBase = imagPtr.baseAddress else { return }
                var split = DSPSplitComplex(realp: realBase, imagp: imagBase)
                buffer.withUnsafeBufferPointer { signal in
                    guard let base = signal.baseAddress else { return }
                    base.withMemoryRebound(to: DSPComplex.self, capacity: n / 2) { complex in
                        vDSP_ctoz(complex, 2, &split, 1, vDSP_Length(n / 2))
                    }
                }
                vDSP_fft_zrip(setup, &split, 1, log2n, FFTDirection(FFT_FORWARD))
                vDSP_zvmags(&split, 1, &magnitudes, 1, vDSP_Length(n / 2))
            }
        }

        var scale = Float(1) / Float(n * n)
        vDSP_vsmul(magnitudes, 1, &scale, &magnitudes, 1, vDSP_Length(n / 2))
        for index in 0..<magnitudes.count {
            magnitudes[index] = sqrt(magnitudes[index])
        }
        return magnitudes
    }

    private static func bandEnergy(_ magnitudes: [Float], band: Int, count: Int) -> Float {
        let binWidth = sampleRate / Double(window)
        let startHz = frequency(band: band, count: count)
        let endHz = band + 1 < count ? frequency(band: band + 1, count: count) : startHz * 1.2
        var startBin = max(1, Int(startHz / binWidth))
        var endBin = min(magnitudes.count - 1, Int(ceil(endHz / binWidth)))
        if endBin < startBin { endBin = startBin }
        startBin = min(startBin, magnitudes.count - 1)
        var peak: Float = 0
        for bin in startBin...endBin {
            peak = max(peak, magnitudes[bin])
        }
        return peak
    }
}

private enum FFTCache {
    static let setup: FFTSetup? = vDSP_create_fftsetup(10, FFTRadix(kFFTRadix2))
}
