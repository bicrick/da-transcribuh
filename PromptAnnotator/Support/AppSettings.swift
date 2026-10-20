import Foundation

enum IslandStyle: String, CaseIterable, Identifiable, Codable {
    case classic
    case compact
    case minimal
    case hidden

    var id: String { rawValue }

    var title: String {
        switch self {
        case .classic: return "Default"
        case .compact: return "Compact"
        case .minimal: return "Minimal"
        case .hidden: return "Hidden"
        }
    }

    var detail: String {
        switch self {
        case .classic: return "Waveform in the middle"
        case .compact: return "Dot, waveform, and time"
        case .minimal: return "Waveform only"
        case .hidden: return "No bar while you record"
        }
    }

    /// Older builds stored Mini for the smaller full bar.
    static func stored(_ raw: String) -> IslandStyle {
        if raw == "mini" { return .compact }
        return IslandStyle(rawValue: raw) ?? .classic
    }
}

@MainActor
final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    @Published var chord: HotkeyChord
    @Published var islandStyle: IslandStyle
    @Published var soundEnabled: Bool
    @Published var soundVolume: Double
    @Published var defaultTool: AnnotationTool
    @Published var defaultColorName: String

    var onChromeChange: (() -> Void)?

    private let defaults: UserDefaults
    private var isLoading = false

    var defaultColor: InkColor {
        InkColor.palette.first { $0.name == defaultColorName } ?? .red
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        isLoading = true
        let keyCode = defaults.object(forKey: Keys.chordKey) as? Int
        let modifiers = defaults.object(forKey: Keys.chordMods) as? Int
        if let keyCode, let modifiers {
            chord = HotkeyChord(keyCode: UInt32(keyCode), carbonModifiers: UInt32(modifiers))
        } else {
            chord = .default
        }
        islandStyle = IslandStyle.stored(defaults.string(forKey: Keys.island) ?? "")
        soundEnabled = defaults.object(forKey: Keys.sound) as? Bool ?? true
        let storedVolume = defaults.object(forKey: Keys.volume) as? Double
        soundVolume = min(1, max(0, storedVolume ?? 0.7))
        defaultTool = AnnotationTool(rawValue: defaults.string(forKey: Keys.tool) ?? "") ?? .pen
        defaultColorName = defaults.string(forKey: Keys.color) ?? InkColor.red.name
        isLoading = false
    }

    func setChord(_ chord: HotkeyChord) -> Bool {
        guard chord.canRegister else { return false }
        guard HotkeyCenter.shared.apply(chord) else { return false }
        self.chord = chord
        defaults.set(Int(chord.keyCode), forKey: Keys.chordKey)
        defaults.set(Int(chord.carbonModifiers), forKey: Keys.chordMods)
        return true
    }

    func setIslandStyle(_ style: IslandStyle) {
        islandStyle = style
        persist(Keys.island, style.rawValue)
        onChromeChange?()
    }

    func setSoundEnabled(_ enabled: Bool) {
        soundEnabled = enabled
        defaults.set(enabled, forKey: Keys.sound)
    }

    func setSoundVolume(_ volume: Double) {
        soundVolume = min(1, max(0, volume))
        defaults.set(soundVolume, forKey: Keys.volume)
    }

    func setDefaultTool(_ tool: AnnotationTool) {
        guard defaultTool != tool else { return }
        defaultTool = tool
        persist(Keys.tool, tool.rawValue)
    }

    func setDefaultColor(_ color: InkColor) {
        guard defaultColorName != color.name else { return }
        defaultColorName = color.name
        persist(Keys.color, color.name)
    }

    private func persist(_ key: String, _ value: String) {
        guard !isLoading else { return }
        defaults.set(value, forKey: key)
    }

    private enum Keys {
        static let chordKey = "hotkey.keyCode"
        static let chordMods = "hotkey.modifiers"
        static let island = "island.style"
        static let sound = "sound.enabled"
        static let volume = "sound.volume"
        static let tool = "tool.default"
        static let color = "ink.default"
    }
}
