import Foundation

/// Low electronic blips for session start, a spoken stop, a silent stop, and a capture.
enum Earcon {
    enum Kind: Equatable {
        case start
        case stopSpoken
        case stopSilent
        case tile
    }

    static func wave(_ kind: Kind, theme: SoundTheme = .classic) -> Data {
        wav(samples(kind, theme: theme))
    }

    static func samples(_ kind: Kind, theme: SoundTheme = .classic) -> [Float] {
        let style = style(for: theme)
        switch (theme, kind) {
        case (.click, .start):
            return phrase([(148, 0.026, 0.5, 0.12), (196, 0.03, 0.55, 0.1)], gaps: [0.018], style: style)
        case (.click, .stopSpoken):
            return phrase([(170, 0.024, 0.48, 0.1), (118, 0.032, 0.52, 0.14)], gaps: [0.016], style: style)
        case (.click, .stopSilent):
            return phrase([(102, 0.038, 0.4, 0.08)], gaps: [], style: style)
        case (.click, .tile):
            return phrase([(156, 0.02, 0.32, 0.08)], gaps: [], style: style)
        case (.deep, .start):
            return phrase([(72, 0.12, 0.7, 0.7), (98, 0.15, 0.76, 0.5)], gaps: [0.04], style: style)
        case (.deep, .stopSpoken):
            return phrase([(90, 0.1, 0.64, 0.45), (60, 0.18, 0.78, 0.72)], gaps: [0.036], style: style)
        case (.deep, .stopSilent):
            return phrase([(56, 0.16, 0.55, 0.3)], gaps: [], style: style)
        case (.deep, .tile):
            return phrase([(84, 0.055, 0.4, 0.28)], gaps: [], style: style)
        case (_, .start):
            return phrase([(112, 0.072, 0.62, theme == .soft ? 0.22 : 0.55), (168, 0.096, theme == .soft ? 0.5 : 0.7, theme == .soft ? 0.16 : 0.34)], gaps: [0.028], style: style)
        case (_, .stopSpoken):
            return phrase([(154, 0.06, theme == .soft ? 0.46 : 0.58, theme == .soft ? 0.14 : 0.32), (92, 0.13, theme == .soft ? 0.54 : 0.72, theme == .soft ? 0.28 : 0.62)], gaps: [0.024], style: style)
        case (_, .stopSilent):
            return phrase([(78, 0.11, theme == .soft ? 0.36 : 0.48, theme == .soft ? 0.08 : 0.16)], gaps: [], style: style)
        case (_, .tile):
            return phrase([(136, 0.04, theme == .soft ? 0.26 : 0.34, theme == .soft ? 0.1 : 0.22)], gaps: [], style: style)
        }
    }

    private static let sampleRate = 44_100.0

    private struct BlipStyle {
        var attack: Double
        var droop: Double
        var saturate: Bool
    }

    private static func style(for theme: SoundTheme) -> BlipStyle {
        switch theme {
        case .classic:
            return BlipStyle(attack: 0.004, droop: 0.08, saturate: true)
        case .soft:
            return BlipStyle(attack: 0.016, droop: 0.03, saturate: false)
        case .click:
            return BlipStyle(attack: 0.0015, droop: 0.02, saturate: true)
        case .deep:
            return BlipStyle(attack: 0.01, droop: 0.11, saturate: true)
        }
    }

    private static func phrase(
        _ notes: [(Double, Double, Double, Double)],
        gaps: [Double],
        style: BlipStyle
    ) -> [Float] {
        var rendered: [Float] = []
        for (index, note) in notes.enumerated() {
            rendered += blip(
                frequency: note.0,
                seconds: note.1,
                amplitude: note.2,
                brightness: note.3,
                style: style
            )
            if index < gaps.count {
                rendered += gap(gaps[index])
            }
        }
        return rendered
    }

    /// A short bass blip. The pitch sags a little, and a quiet octave keeps it audible on small speakers.
    private static func blip(
        frequency: Double,
        seconds: Double,
        amplitude: Double,
        brightness: Double,
        style: BlipStyle
    ) -> [Float] {
        let count = max(1, Int(sampleRate * seconds))
        let attack = min(style.attack, seconds * 0.45)
        var phase = 0.0
        var raw = [Float]()
        raw.reserveCapacity(count)
        for index in 0..<count {
            let t = Double(index) / sampleRate
            let progress = Double(index) / Double(max(count - 1, 1))
            let freq = frequency * (1 - style.droop * progress)
            phase += 2 * .pi * freq / sampleRate
            let env: Double
            if t < attack {
                env = t / max(attack, 0.0001)
            } else {
                let tau = max(seconds - attack, 0.01) / 2.8
                env = exp(-(t - attack) / tau)
            }
            let tone = sin(phase) + brightness * sin(2 * phase) + brightness * 0.2 * sin(3 * phase)
            let shaped = style.saturate ? tanh(tone * 1.15) : tone
            raw.append(Float(shaped * env))
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
