import Foundation

/// Low electronic blips for session start, a spoken stop, a silent stop, and a capture.
enum Earcon {
    enum Kind: Equatable {
        case start
        case stopSpoken
        case stopSilent
        case tile
    }

    static func wave(_ kind: Kind) -> Data {
        wav(samples(kind))
    }

    static func samples(_ kind: Kind) -> [Float] {
        switch kind {
        case .start:
            return blip(frequency: 112, seconds: 0.072, amplitude: 0.62, brightness: 0.55)
                + gap(0.028)
                + blip(frequency: 168, seconds: 0.096, amplitude: 0.7, brightness: 0.34)
        case .stopSpoken:
            return blip(frequency: 154, seconds: 0.06, amplitude: 0.58, brightness: 0.32)
                + gap(0.024)
                + blip(frequency: 92, seconds: 0.13, amplitude: 0.72, brightness: 0.62)
        case .stopSilent:
            return blip(frequency: 78, seconds: 0.11, amplitude: 0.48, brightness: 0.16)
        case .tile:
            return blip(frequency: 136, seconds: 0.04, amplitude: 0.34, brightness: 0.22)
        }
    }

    private static let sampleRate = 44_100.0

    /// A short bass blip. The pitch sags a little, and a quiet octave keeps it audible on small speakers.
    private static func blip(frequency: Double, seconds: Double, amplitude: Double, brightness: Double) -> [Float] {
        let count = max(1, Int(sampleRate * seconds))
        let attack = min(0.004, seconds * 0.16)
        let droop = 0.08
        var phase = 0.0
        var raw = [Float]()
        raw.reserveCapacity(count)
        for index in 0..<count {
            let t = Double(index) / sampleRate
            let progress = Double(index) / Double(max(count - 1, 1))
            let freq = frequency * (1 - droop * progress)
            phase += 2 * .pi * freq / sampleRate
            let env: Double
            if t < attack {
                env = t / max(attack, 0.0001)
            } else {
                let tau = max(seconds - attack, 0.01) / 2.8
                env = exp(-(t - attack) / tau)
            }
            let tone = sin(phase) + brightness * sin(2 * phase) + brightness * 0.2 * sin(3 * phase)
            raw.append(Float(tanh(tone * 1.15) * env))
        }
        let peak = raw.map { abs($0) }.max() ?? 1
        let scale = Float(amplitude) / max(peak, 0.0001)
        return raw.map { $0 * scale }
    }

    private static func gap(_ seconds: Double) -> [Float] {
        Array(repeating: 0, count: Int(sampleRate * seconds))
    }

    private static func wav(_ samples: [Float]) -> Data {
        let dataSize = samples.count * 2
        var data = Data()
        data.append(contentsOf: [0x52, 0x49, 0x46, 0x46]) // RIFF
        data.append(uint32(UInt32(36 + dataSize)))
        data.append(contentsOf: [0x57, 0x41, 0x56, 0x45]) // WAVE
        data.append(contentsOf: [0x66, 0x6D, 0x74, 0x20]) // fmt
        data.append(uint32(16))
        data.append(uint16(1))
        data.append(uint16(1))
        data.append(uint32(UInt32(sampleRate)))
        data.append(uint32(UInt32(sampleRate) * 2))
        data.append(uint16(2))
        data.append(uint16(16))
        data.append(contentsOf: [0x64, 0x61, 0x74, 0x61]) // data
        data.append(uint32(UInt32(dataSize)))
        for sample in samples {
            let clamped = max(-1, min(1, sample))
            var value = Int16(clamped * 32_000).littleEndian
            withUnsafeBytes(of: &value) { data.append(contentsOf: $0) }
        }
        return data
    }

    private static func uint32(_ value: UInt32) -> Data {
        var little = value.littleEndian
        return withUnsafeBytes(of: &little) { Data($0) }
    }

    private static func uint16(_ value: UInt16) -> Data {
        var little = value.littleEndian
        return withUnsafeBytes(of: &little) { Data($0) }
    }
}
