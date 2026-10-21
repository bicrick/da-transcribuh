import CoreGraphics
import Foundation

enum SoundTheme: String, CaseIterable, Identifiable, Codable {
    case classic
    case soft
    case click
    case deep

    var id: String { rawValue }

    var title: String {
        switch self {
        case .classic: return "Classic"
        case .soft: return "Soft"
        case .click: return "Click"
        case .deep: return "Deep"
        }
    }

    var detail: String {
        switch self {
        case .classic: return "Low blips. Start rises, and a spoken stop falls."
        case .soft: return "The same shape, rounder and a little quieter."
        case .click: return "Short dry ticks."
        case .deep: return "Slower bass tones."
        }
    }

    var gain: Float {
        switch self {
        case .classic: return 1
        case .soft: return 0.78
        case .click: return 0.9
        case .deep: return 1
        }
    }
}

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
    @Published var cancelChord: HotkeyChord?
    @Published var pushToTalk: Bool
    @Published var islandStyle: IslandStyle
    @Published var soundEnabled: Bool
    @Published var soundVolume: Double
    @Published var soundTheme: SoundTheme
    @Published var inputDeviceUID: String
    @Published var raiseInputVolume: Bool
    @Published var defaultTool: AnnotationTool
    @Published var defaultColorName: String
    @Published var launchAtLogin: Bool
    @Published var keepWindowOnTop: Bool
    @Published var errorLogging: Bool
    @Published var showInDock: Bool
    @Published var silenceStopSeconds: Double
    /// Optional SpeechGate floor from quiet-room calibration; `nil` keeps the default 0.28.
    @Published var speechGateThreshold: Double?
    @Published var maxSessionMinutes: Double
    @Published var normalizeSpeech: Bool
    @Published var pasteOnStop: Bool
    @Published var returnOnShift: Bool
    @Published var capitalizeTranscript: Bool
    @Published var speechModel: String
    @Published var loginItemNote: String?

    var onChromeChange: (() -> Void)?
    var onAppChange: (() -> Void)?

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
        cancelChord = Self.chord(key: Keys.cancelKey, mods: Keys.cancelMods, defaults: defaults)
        pushToTalk = defaults.bool(forKey: Keys.pushToTalk)
        islandStyle = IslandStyle.stored(defaults.string(forKey: Keys.island) ?? "")
        soundEnabled = defaults.object(forKey: Keys.sound) as? Bool ?? true
        let storedVolume = defaults.object(forKey: Keys.volume) as? Double
        soundVolume = min(1, max(0, storedVolume ?? 0.7))
        soundTheme = SoundTheme(rawValue: defaults.string(forKey: Keys.theme) ?? "") ?? .classic
        inputDeviceUID = defaults.string(forKey: Keys.input) ?? ""
        raiseInputVolume = defaults.bool(forKey: Keys.raiseInput)
        defaultTool = AnnotationTool(rawValue: defaults.string(forKey: Keys.tool) ?? "") ?? .pen
        defaultColorName = defaults.string(forKey: Keys.color) ?? InkColor.red.name
        launchAtLogin = defaults.bool(forKey: Keys.login)
        keepWindowOnTop = defaults.bool(forKey: Keys.onTop)
        errorLogging = defaults.bool(forKey: Keys.errorLog)
        showInDock = defaults.object(forKey: Keys.dock) as? Bool ?? true
        silenceStopSeconds = defaults.object(forKey: Keys.silence) as? Double ?? 0
        if defaults.object(forKey: Keys.speechGate) != nil {
            let raw = defaults.double(forKey: Keys.speechGate)
            speechGateThreshold = Double(
                min(
                    QuietRoomCalibration.maximumThreshold,
                    max(QuietRoomCalibration.minimumThreshold, CGFloat(raw))
                )
            )
        } else {
            speechGateThreshold = nil
        }
        maxSessionMinutes = defaults.object(forKey: Keys.maxMinutes) as? Double ?? 0
        normalizeSpeech = defaults.bool(forKey: Keys.normalize)
        SpeechGate.setCalibratedThreshold(speechGateThreshold.map { CGFloat($0) })
        pasteOnStop = defaults.object(forKey: Keys.pasteOnStop) as? Bool ?? true
        returnOnShift = defaults.bool(forKey: Keys.returnOnShift)
        capitalizeTranscript = defaults.bool(forKey: Keys.capitalize)
        speechModel = SpeechModelChoice.stored(defaults.string(forKey: Keys.speechModel)).variant
        loginItemNote = nil
        isLoading = false
    }

    private static func chord(key: String, mods: String, defaults: UserDefaults) -> HotkeyChord? {
        guard let keyCode = defaults.object(forKey: key) as? Int,
              let modifiers = defaults.object(forKey: mods) as? Int else { return nil }
        let chord = HotkeyChord(keyCode: UInt32(keyCode), carbonModifiers: UInt32(modifiers))
        return chord.canRegister ? chord : nil
    }

    func setChord(_ chord: HotkeyChord) -> Bool {
        guard chord.canRegister else { return false }
        guard chord != cancelChord else { return false }
        guard HotkeyCenter.shared.apply(chord) else { return false }
        self.chord = chord
        defaults.set(Int(chord.keyCode), forKey: Keys.chordKey)
        defaults.set(Int(chord.carbonModifiers), forKey: Keys.chordMods)
        return true
    }

    func setCancelChord(_ chord: HotkeyChord?) -> Bool {
        if let chord {
            guard chord.canRegister, chord != self.chord else { return false }
        }
        guard HotkeyCenter.shared.applyCancel(chord) else { return false }
        cancelChord = chord
        if let chord {
            defaults.set(Int(chord.keyCode), forKey: Keys.cancelKey)
            defaults.set(Int(chord.carbonModifiers), forKey: Keys.cancelMods)
        } else {
            defaults.removeObject(forKey: Keys.cancelKey)
            defaults.removeObject(forKey: Keys.cancelMods)
        }
        return true
    }

    func setPushToTalk(_ enabled: Bool) {
        pushToTalk = enabled
        persist(Keys.pushToTalk, enabled)
    }

    func setSoundTheme(_ theme: SoundTheme) {
        soundTheme = theme
        persist(Keys.theme, theme.rawValue)
    }

    func setInputDeviceUID(_ uid: String) {
        inputDeviceUID = uid
        persist(Keys.input, uid)
    }

    func setRaiseInputVolume(_ enabled: Bool) {
        raiseInputVolume = enabled
        persist(Keys.raiseInput, enabled)
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            try LoginItem.setEnabled(enabled)
            launchAtLogin = enabled
            loginItemNote = nil
            persist(Keys.login, enabled)
        } catch {
            loginItemNote = error.localizedDescription
        }
    }

    func setKeepWindowOnTop(_ enabled: Bool) {
        keepWindowOnTop = enabled
        persist(Keys.onTop, enabled)
        onAppChange?()
    }

    func setErrorLogging(_ enabled: Bool) {
        errorLogging = enabled
        persist(Keys.errorLog, enabled)
    }

    func setShowInDock(_ enabled: Bool) {
        showInDock = enabled
        persist(Keys.dock, enabled)
        onAppChange?()
    }

    func setSilenceStopSeconds(_ seconds: Double) {
        silenceStopSeconds = seconds
        persist(Keys.silence, seconds)
    }

    func setSpeechGateThreshold(_ value: Double?) {
        guard !isLoading else { return }
        if let value {
            let clamped = Double(
                min(
                    QuietRoomCalibration.maximumThreshold,
                    max(QuietRoomCalibration.minimumThreshold, CGFloat(value))
                )
            )
            speechGateThreshold = clamped
            defaults.set(clamped, forKey: Keys.speechGate)
            SpeechGate.setCalibratedThreshold(CGFloat(clamped))
        } else {
            speechGateThreshold = nil
            defaults.removeObject(forKey: Keys.speechGate)
            SpeechGate.setCalibratedThreshold(nil)
        }
    }

    var hasSpeechGateCalibration: Bool {
        speechGateThreshold != nil
    }

    func setMaxSessionMinutes(_ minutes: Double) {
        maxSessionMinutes = minutes
        persist(Keys.maxMinutes, minutes)
    }

    func setNormalizeSpeech(_ enabled: Bool) {
        normalizeSpeech = enabled
        persist(Keys.normalize, enabled)
    }

    func setPasteOnStop(_ enabled: Bool) {
        pasteOnStop = enabled
        persist(Keys.pasteOnStop, enabled)
    }

    func setReturnOnShift(_ enabled: Bool) {
        returnOnShift = enabled
        persist(Keys.returnOnShift, enabled)
    }

    func setCapitalizeTranscript(_ enabled: Bool) {
        capitalizeTranscript = enabled
        persist(Keys.capitalize, enabled)
    }

    func setSpeechModel(_ variant: String) {
        speechModel = SpeechModelChoice.stored(variant).variant
        persist(Keys.speechModel, speechModel)
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

    private func persist(_ key: String, _ value: Bool) {
        guard !isLoading else { return }
        defaults.set(value, forKey: key)
    }

    private func persist(_ key: String, _ value: Double) {
        guard !isLoading else { return }
        defaults.set(value, forKey: key)
    }

    private enum Keys {
        static let chordKey = "hotkey.keyCode"
        static let chordMods = "hotkey.modifiers"
        static let cancelKey = "hotkey.cancel.keyCode"
        static let cancelMods = "hotkey.cancel.modifiers"
        static let pushToTalk = "hotkey.pushToTalk"
        static let island = "island.style"
        static let sound = "sound.enabled"
        static let volume = "sound.volume"
        static let theme = "sound.theme"
        static let input = "audio.inputUID"
        static let raiseInput = "audio.raiseVolume"
        static let tool = "tool.default"
        static let color = "ink.default"
        static let login = "app.launchAtLogin"
        static let onTop = "app.windowOnTop"
        static let errorLog = "app.errorLog"
        static let dock = "app.showInDock"
        static let silence = "session.silenceStop"
        static let speechGate = "session.speechGateThreshold"
        static let maxMinutes = "session.maxMinutes"
        static let normalize = "session.normalize"
        static let pasteOnStop = "session.pasteOnStop"
        static let returnOnShift = "session.returnOnShift"
        static let capitalize = "session.capitalize"
        static let speechModel = SpeechModelChoice.defaultsKey
    }
}
