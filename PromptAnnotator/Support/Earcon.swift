import Foundation

/// Short tones for session start, a spoken stop, a silent stop, and a capture.
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
            return blip(frequency: 698, seconds: 0.055, amplitude: 0.34)
                + gap(0.02)
                + blip(frequency: 1174, seconds: 0.1, amplitude: 0.42)
        case .stopSpoken:
            return blip(frequency: 988, seconds: 0.06, amplitude: 0.36)
                + gap(0.018)
                + blip(frequency: 659, seconds: 0.14, amplitude: 0.4)
        case .stopSilent:
            return blip(frequency: 415, seconds: 0.11, amplitude: 0.24)
        case .tile:
            return blip(frequency: 1568, seconds: 0.028, amplitude: 0.18)
        }
    }

    private static let sampleRate = 44_100.0

    private static func blip(frequency: Double, seconds: Double, amplitude: Double) -> [Float] {
        let count = max(1, Int(sampleRate * seconds))
        return (0..<count).map { index in
            let progress = Double(index) / Double(max(count - 1, 1))
            let t = Double(index) / sampleRate
            let frequencyNow = frequency * (1 - 0.18 * progress)
            let window = sin(.pi * progress)
            let fundamental = sin(2 * .pi * frequencyNow * t)
            let overtone = 0.16 * sin(4 * .pi * frequencyNow * t)
            return Float((fundamental + overtone) * window * window * amplitude)
        }
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
