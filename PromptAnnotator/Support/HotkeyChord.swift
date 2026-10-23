import AppKit
import Carbon.HIToolbox
import Foundation

/// The session toggle. Shift is not allowed: while a session is running, Shift draws.
/// Command-Space and Option-Command-Space stay with Spotlight / Finder search.
/// Option-Space is the default Start/Stop chord (Carbon consumes it so it won’t type NBSP).
struct HotkeyChord: Equatable, Codable {
    var keyCode: UInt32
    var carbonModifiers: UInt32

    /// Default Start/Stop: Option-Space.
    static let `default` = HotkeyChord(
        keyCode: UInt32(kVK_Space),
        carbonModifiers: UInt32(optionKey)
    )

    /// Pre-⌥Space default — used once to migrate users who never customized.
    static let legacyDefault = HotkeyChord(
        keyCode: UInt32(kVK_Space),
        carbonModifiers: UInt32(controlKey | optionKey)
    )

    var normalizedModifiers: UInt32 {
        carbonModifiers & UInt32(cmdKey | shiftKey | optionKey | controlKey)
    }

    var includesShift: Bool {
        normalizedModifiers & UInt32(shiftKey) != 0
    }

    /// True when this chord would take Command-Space or Option-Command-Space.
    var takesOverSystemShortcut: Bool {
        guard keyCode == UInt32(kVK_Space) else { return false }
        switch normalizedModifiers {
        case UInt32(cmdKey), UInt32(cmdKey | optionKey):
            return true
        default:
            return false
        }
    }

    /// F1–F12 may register without a modifier; everything else needs at least one.
    /// Carbon's F-key codes are not contiguous (kVK_F1 = 0x7A, kVK_F12 = 0x6F), so a
    /// `kVK_F1...kVK_F12` range traps at runtime. Use an explicit set instead.
    var isFunctionKey: Bool {
        Self.functionKeyCodes.contains(keyCode)
    }

    private static let functionKeyCodes: Set<UInt32> = [
        kVK_F1, kVK_F2, kVK_F3, kVK_F4, kVK_F5, kVK_F6,
        kVK_F7, kVK_F8, kVK_F9, kVK_F10, kVK_F11, kVK_F12,
    ].reduce(into: []) { $0.insert(UInt32($1)) }

    var canRegister: Bool {
        canRegister(allowingShift: false)
    }

    /// Clipboard chords may include Shift (e.g. ⌘⇧C). Recording chords may not.
    func canRegister(allowingShift: Bool) -> Bool {
        (normalizedModifiers != 0 || isFunctionKey)
            && (allowingShift || !includesShift)
            && !takesOverSystemShortcut
    }

    var rejection: String? {
        rejection(allowingShift: false)
    }

    func rejection(allowingShift: Bool) -> String? {
        if normalizedModifiers == 0 && !isFunctionKey {
            return "Add at least one modifier, or use a function key."
        }
        if includesShift && !allowingShift {
            return "Shift is held to draw, so the shortcut cannot include Shift."
        }
        if takesOverSystemShortcut {
            return "Command-Space and Option-Command-Space stay with the system."
        }
        return nil
    }

    /// Default clipboard-history chord: ⌘⇧C.
    static let clipboardDefault = HotkeyChord(
        keyCode: UInt32(kVK_ANSI_C),
        carbonModifiers: UInt32(cmdKey | shiftKey)
    )

    var display: String {
        var symbols = ""
        let mods = normalizedModifiers
        if mods & UInt32(controlKey) != 0 { symbols += "⌃" }
        if mods & UInt32(optionKey) != 0 { symbols += "⌥" }
        if mods & UInt32(shiftKey) != 0 { symbols += "⇧" }
        if mods & UInt32(cmdKey) != 0 { symbols += "⌘" }
        return symbols + keyTitle
    }

    /// Separate keycaps, modifiers first, then the key. Option-Space is ⌥, Space.
    var keycaps: [String] {
        var caps: [String] = []
        let mods = normalizedModifiers
        if mods & UInt32(controlKey) != 0 { caps.append("⌃") }
        if mods & UInt32(optionKey) != 0 { caps.append("⌥") }
        if mods & UInt32(shiftKey) != 0 { caps.append("⇧") }
        if mods & UInt32(cmdKey) != 0 { caps.append("⌘") }
        caps.append(keyTitle)
        return caps
    }

    var keyTitle: String {
        switch keyCode {
        case UInt32(kVK_Space): return "Space"
        case UInt32(kVK_Return): return "Return"
        case UInt32(kVK_ANSI_KeypadEnter): return "Enter"
        case UInt32(kVK_Escape): return "Esc"
        case UInt32(kVK_Tab): return "Tab"
        case UInt32(kVK_Delete): return "Delete"
        case UInt32(kVK_ForwardDelete): return "Fwd Del"
        case UInt32(kVK_LeftArrow): return "Left"
        case UInt32(kVK_RightArrow): return "Right"
        case UInt32(kVK_UpArrow): return "Up"
        case UInt32(kVK_DownArrow): return "Down"
        case UInt32(kVK_F1): return "F1"
        case UInt32(kVK_F2): return "F2"
        case UInt32(kVK_F3): return "F3"
        case UInt32(kVK_F4): return "F4"
        case UInt32(kVK_F5): return "F5"
        case UInt32(kVK_F6): return "F6"
        case UInt32(kVK_F7): return "F7"
        case UInt32(kVK_F8): return "F8"
        case UInt32(kVK_F9): return "F9"
        case UInt32(kVK_F10): return "F10"
        case UInt32(kVK_F11): return "F11"
        case UInt32(kVK_F12): return "F12"
        case UInt32(kVK_ANSI_Grave): return "`"
        default:
            return Self.ansiTitles[keyCode] ?? "Key \(keyCode)"
        }
    }

    private static let ansiTitles: [UInt32: String] = [
        UInt32(kVK_ANSI_A): "A", UInt32(kVK_ANSI_S): "S", UInt32(kVK_ANSI_D): "D",
        UInt32(kVK_ANSI_F): "F", UInt32(kVK_ANSI_H): "H", UInt32(kVK_ANSI_G): "G",
        UInt32(kVK_ANSI_Z): "Z", UInt32(kVK_ANSI_X): "X", UInt32(kVK_ANSI_C): "C",
        UInt32(kVK_ANSI_V): "V", UInt32(kVK_ANSI_B): "B", UInt32(kVK_ANSI_Q): "Q",
        UInt32(kVK_ANSI_W): "W", UInt32(kVK_ANSI_E): "E", UInt32(kVK_ANSI_R): "R",
        UInt32(kVK_ANSI_Y): "Y", UInt32(kVK_ANSI_T): "T", UInt32(kVK_ANSI_1): "1",
        UInt32(kVK_ANSI_2): "2", UInt32(kVK_ANSI_3): "3", UInt32(kVK_ANSI_4): "4",
        UInt32(kVK_ANSI_6): "6", UInt32(kVK_ANSI_5): "5", UInt32(kVK_ANSI_Equal): "=",
        UInt32(kVK_ANSI_9): "9", UInt32(kVK_ANSI_7): "7", UInt32(kVK_ANSI_Minus): "-",
        UInt32(kVK_ANSI_8): "8", UInt32(kVK_ANSI_0): "0", UInt32(kVK_ANSI_RightBracket): "]",
        UInt32(kVK_ANSI_O): "O", UInt32(kVK_ANSI_U): "U", UInt32(kVK_ANSI_LeftBracket): "[",
        UInt32(kVK_ANSI_I): "I", UInt32(kVK_ANSI_P): "P", UInt32(kVK_ANSI_L): "L",
        UInt32(kVK_ANSI_J): "J", UInt32(kVK_ANSI_Quote): "'", UInt32(kVK_ANSI_K): "K",
        UInt32(kVK_ANSI_Semicolon): ";", UInt32(kVK_ANSI_Backslash): "\\",
        UInt32(kVK_ANSI_Comma): ",", UInt32(kVK_ANSI_Slash): "/", UInt32(kVK_ANSI_N): "N",
        UInt32(kVK_ANSI_M): "M", UInt32(kVK_ANSI_Period): ".",
    ]
}

extension HotkeyChord {
    init(event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        var carbon: UInt32 = 0
        if flags.contains(.command) { carbon |= UInt32(cmdKey) }
        if flags.contains(.shift) { carbon |= UInt32(shiftKey) }
        if flags.contains(.option) { carbon |= UInt32(optionKey) }
        if flags.contains(.control) { carbon |= UInt32(controlKey) }
        self.init(keyCode: UInt32(event.keyCode), carbonModifiers: carbon)
    }
}

/// Shared capture outcome for the recording Start/Stop chord (Home + General).
/// One path into `AppSettings.setChord` so both UIs stay in sync.
enum RecordingChordCapture {
    enum Outcome: Equatable {
        case cancelled
        case restoredDefault(success: Bool)
        case rejected(String)
        case saved(success: Bool)
    }

    /// Esc cancels; Delete / Forward Delete restores ⌥Space; otherwise validate + `setChord`.
    @MainActor
    static func applyToggleEvent(_ event: NSEvent, settings: AppSettings) -> Outcome {
        let bare = event.modifierFlags.intersection(.deviceIndependentFlagsMask).isEmpty
        if bare, event.keyCode == 53 { // Esc
            return .cancelled
        }
        if bare, event.keyCode == 51 || event.keyCode == 117 { // Delete / Fwd Del
            let ok = settings.setChord(.default)
            return .restoredDefault(success: ok)
        }
        let chord = HotkeyChord(event: event)
        if let rejection = chord.rejection {
            return .rejected(rejection)
        }
        let ok = settings.setChord(chord)
        return .saved(success: ok)
    }

    static func message(for outcome: Outcome) -> String? {
        switch outcome {
        case .cancelled:
            return nil
        case .restoredDefault(let success):
            return success ? nil : "macOS would not register the default shortcut."
        case .rejected(let reason):
            return reason
        case .saved(let success):
            return success ? nil : "That shortcut is already used, or macOS would not register it."
        }
    }
}
