import AppKit
import Carbon.HIToolbox
import Foundation

/// The session toggle. Shift is not allowed: while a session is running, Shift draws.
/// Option-Space, Command-Space, and Option-Command-Space stay with the system.
struct HotkeyChord: Equatable, Codable {
    var keyCode: UInt32
    var carbonModifiers: UInt32

    static let `default` = HotkeyChord(
        keyCode: UInt32(kVK_Space),
        carbonModifiers: UInt32(controlKey | optionKey)
    )

    var normalizedModifiers: UInt32 {
        carbonModifiers & UInt32(cmdKey | shiftKey | optionKey | controlKey)
    }

    var includesShift: Bool {
        normalizedModifiers & UInt32(shiftKey) != 0
    }

    /// True when this chord would take Option-Space, Command-Space, or Option-Command-Space.
    var takesOverSystemShortcut: Bool {
        guard keyCode == UInt32(kVK_Space) else { return false }
        switch normalizedModifiers {
        case UInt32(optionKey), UInt32(cmdKey), UInt32(cmdKey | optionKey):
            return true
        default:
            return false
        }
    }

    var canRegister: Bool {
        normalizedModifiers != 0 && !includesShift && !takesOverSystemShortcut
    }

    var rejection: String? {
        if normalizedModifiers == 0 {
            return "Add at least one modifier."
        }
        if includesShift {
            return "Shift is held to draw, so the shortcut cannot include Shift."
        }
        if takesOverSystemShortcut {
            return "Option-Space, Command-Space, and Option-Command-Space stay with the system."
        }
        return nil
    }

    var display: String {
        var symbols = ""
        let mods = normalizedModifiers
        if mods & UInt32(controlKey) != 0 { symbols += "⌃" }
        if mods & UInt32(optionKey) != 0 { symbols += "⌥" }
        if mods & UInt32(shiftKey) != 0 { symbols += "⇧" }
        if mods & UInt32(cmdKey) != 0 { symbols += "⌘" }
        return symbols + keyTitle
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
