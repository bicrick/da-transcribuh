import Foundation

/// Lifts a quiet take toward a speaking level. Silence and already-loud takes stay as they are.
enum SampleNormalize {
    static func apply(_ samples: [Float], enabled: Bool) -> [Float] {
        guard enabled, !samples.isEmpty else { return samples }
        var peak: Float = 0
        for sample in samples {
            peak = max(peak, abs(sample))
        }
        guard peak > 0.02, peak < 0.6 else { return samples }
        let scale = 0.9 / peak
        return samples.map { min(1, max(-1, $0 * scale)) }
    }
}
