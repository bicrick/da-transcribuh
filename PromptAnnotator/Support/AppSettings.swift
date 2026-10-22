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
        case .classic: return "Record square, timer, and waveform — the everyday size"
        case .compact: return "Same layout, tighter height and type"
        case .minimal: return "Waveform only"
        case .hidden: return "No bar while you record"
        }
    }

    /// Older builds stored Mini for the smaller full bar; empty / unknown → Default (classic).
    /// Classic users keep the key and pick up the new default metrics automatically.
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
    @Published var appearance: AppAppearance
    @Published var silenceStopSeconds: Double
    @Published var maxSessionMinutes: Double
    @Published var normalizeSpeech: Bool
    @Published var pasteOnStop: Bool
    @Published var returnOnShift: Bool
    @Published var capitalizeTranscript: Bool
    @Published var speechModel: String
    @Published var speechEngine: SpeechEngineKind
    @Published var customModelID: String?
    @Published var customModels: [CustomWhisperModel]
    @Published var openAIBaseURL: String
    @Published var openAIModel: String
    @Published var loginItemNote: String?

    var onChromeChange: (() -> Void)?
    var onAppChange: (() -> Void)?
    /// Fired after the speech engine or model selection changes so the session can reload.
    var onSpeechSelectionChange: (() -> Void)?

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
        appearance = AppAppearance.stored(defaults.string(forKey: Keys.appearance))
        silenceStopSeconds = defaults.object(forKey: Keys.silence) as? Double ?? 0
        maxSessionMinutes = defaults.object(forKey: Keys.maxMinutes) as? Double ?? 0
        normalizeSpeech = defaults.bool(forKey: Keys.normalize)
        pasteOnStop = defaults.object(forKey: Keys.pasteOnStop) as? Bool ?? true
        returnOnShift = defaults.bool(forKey: Keys.returnOnShift)
        capitalizeTranscript = defaults.bool(forKey: Keys.capitalize)
        speechModel = SpeechModelChoice.stored(defaults.string(forKey: Keys.speechModel)).variant
        speechEngine = SpeechEngineKind.stored(defaults.string(forKey: Keys.speechEngine))
        customModels = CustomWhisperCatalog.load(defaults: defaults)
        let customID = CustomWhisperCatalog.selectedCustomID(defaults: defaults)
        customModelID = customID.flatMap { id in
            customModels.contains(where: { $0.id == id }) ? id : nil
        }
        openAIBaseURL = OpenAICompatibleTranscriber.storedBaseURL(defaults: defaults)
        openAIModel = OpenAICompatibleTranscriber.storedModel(defaults: defaults)
        loginItemNote = nil
        isLoading = false
        appearance.applyToApp()
    }

    func setAppearance(_ mode: AppAppearance) {
        guard appearance != mode else {
            mode.applyToApp()
            return
        }
        appearance = mode
        persist(Keys.appearance, mode.rawValue)
        mode.applyToApp()
        onAppChange?()
    }

    func cycleAppearance() {
        setAppearance(appearance.next)
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
        customModelID = nil
        CustomWhisperCatalog.setSelectedCustomID(nil, defaults: defaults)
        persist(Keys.speechModel, speechModel)
        notifySpeechSelectionChange()
    }

    func setSpeechEngine(_ engine: SpeechEngineKind) {
        guard speechEngine != engine else { return }
        speechEngine = engine
        persist(Keys.speechEngine, engine.rawValue)
        notifySpeechSelectionChange()
    }

    func selectCustomModel(_ id: String) {
        guard customModels.contains(where: { $0.id == id }) else { return }
        customModelID = id
        CustomWhisperCatalog.setSelectedCustomID(id, defaults: defaults)
        notifySpeechSelectionChange()
    }

    func addCustomModel(_ model: CustomWhisperModel) {
        CustomWhisperCatalog.upsert(model, defaults: defaults)
        customModels = CustomWhisperCatalog.load(defaults: defaults)
    }

    func removeCustomModel(id: String) {
        CustomWhisperCatalog.remove(id: id, defaults: defaults)
        customModels = CustomWhisperCatalog.load(defaults: defaults)
        if customModelID == id {
            customModelID = nil
            notifySpeechSelectionChange()
        }
    }

    func setOpenAIBaseURL(_ value: String) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        openAIBaseURL = trimmed.isEmpty ? "https://api.openai.com" : trimmed
        persist(Keys.openAIBaseURL, openAIBaseURL)
    }

    func setOpenAIModel(_ value: String) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        openAIModel = trimmed.isEmpty ? "whisper-1" : trimmed
        persist(Keys.openAIModel, openAIModel)
    }

    func setOpenAIAPIKey(_ value: String) {
        KeychainStore.set(value, account: KeychainStore.openAIAPIKeyAccount)
        notifySpeechSelectionChange()
    }

    func openAIAPIKey() -> String {
        KeychainStore.get(account: KeychainStore.openAIAPIKeyAccount) ?? ""
    }

    var usesCustomWhisperModel: Bool {
        customModelID != nil
    }

    var liveCaptionsEnabled: Bool {
        speechEngine == .whisperKit
    }

    /// Clears a broken custom selection and restores the built-in balanced model (no reload notify).
    func fallBackToDefaultWhisperModel() {
        customModelID = nil
        CustomWhisperCatalog.setSelectedCustomID(nil, defaults: defaults)
        speechModel = SpeechModelChoice.recommended.variant
        persist(Keys.speechModel, speechModel)
        customModels = CustomWhisperCatalog.load(defaults: defaults)
    }

    private func notifySpeechSelectionChange() {
        guard !isLoading else { return }
        onSpeechSelectionChange?()
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
        static let appearance = "app.appearance"
        static let silence = "session.silenceStop"
        static let maxMinutes = "session.maxMinutes"
        static let normalize = "session.normalize"
        static let pasteOnStop = "session.pasteOnStop"
        static let returnOnShift = "session.returnOnShift"
        static let capitalize = "session.capitalize"
        static let speechModel = SpeechModelChoice.defaultsKey
        static let speechEngine = SpeechEngineKind.defaultsKey
        static let openAIBaseURL = OpenAICompatibleTranscriber.baseURLKey
        static let openAIModel = OpenAICompatibleTranscriber.modelKey
    }
}
