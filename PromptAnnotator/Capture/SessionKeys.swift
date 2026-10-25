import Carbon.HIToolbox
import CoreGraphics

/// A modifier held during a session. One grabs the screen, the other draws.
enum SessionModifier: String, CaseIterable, Codable, Identifiable {
    case shift
    case control
    case option

    var id: String { rawValue }

    var title: String {
        switch self {
        case .shift: return "Shift"
        case .control: return "Control"
        case .option: return "Option"
        }
    }

    var glyph: String {
        switch self {
        case .shift: return "⇧"
        case .control: return "⌃"
        case .option: return "⌥"
        }
    }

    var eventFlag: CGEventFlags {
        switch self {
        case .shift: return .maskShift
        case .control: return .maskControl
        case .option: return .maskAlternate
        }
    }

    var carbonMask: UInt32 {
        switch self {
        case .shift: return UInt32(shiftKey)
        case .control: return UInt32(controlKey)
        case .option: return UInt32(optionKey)
        }
    }

    /// Modifiers that may be held for screenshot mode.
    static let screenshotChoices: [SessionModifier] = [.shift, .control, .option]
    /// Modifiers that may be held for drawing. `nil` in the picker means Off.
    static let annotateChoices: [SessionModifier] = [.control, .option]
}

/// The keys held during a session and the decisions they drive.
/// Pure so the state machine is testable without an event tap.
enum SessionKeys {
    enum Hold: Equatable {
        case none
        /// The screenshot key is down: crosshair, drag to grab.
        case screenshot
        /// The annotate key is down: drags draw with the armed tool.
        case annotate
    }

    struct Bindings: Equatable {
        var screenshot: SessionModifier
        var annotate: SessionModifier?

        static let standard = Bindings(screenshot: .shift, annotate: .control)

        func key(for hold: Hold) -> SessionModifier? {
            switch hold {
            case .none: return nil
            case .screenshot: return screenshot
            case .annotate: return annotate
            }
        }

        var flags: CGEventFlags {
            var all = screenshot.eventFlag
            if let annotate { all.insert(annotate.eventFlag) }
            return all
        }

        /// "Talk, or hold Shift and drag" on Home.
        var grabPhrase: String { "hold \(screenshot.title) and drag" }

        /// One line on how to draw, for Home and onboarding.
        var drawSentence: String {
            if let annotate {
                return "Hold \(annotate.title) to draw. Release it to save that tile."
            }
            return "Hold \(screenshot.title), pick a pen on the bar, and draw. Release \(screenshot.title) to save that tile."
        }
    }

    /// Modifiers that decide whether a session key was pressed on its own.
    static let watchedFlags: CGEventFlags = [.maskShift, .maskControl, .maskAlternate, .maskCommand]

    /// The hold after a modifier change.
    /// A hold starts only when its key is the only watched modifier down (so ⌘⇧4 and
    /// ⌥⇧ shortcuts stay with their apps). `ignoring` drops the push-to-talk chord's
    /// modifiers while that chord is held. Once started, a hold lasts while its key
    /// stays down, so ⌘Z still works mid-drawing. ⌘ ends a screenshot hold.
    static func hold(
        after flags: CGEventFlags,
        current: Hold,
        bindings: Bindings,
        ignoring: CGEventFlags = [],
        suppressed: Bool
    ) -> Hold {
        if let key = bindings.key(for: current), flags.contains(key.eventFlag) {
            // ⌘ joining the screenshot key belongs to a shortcut such as ⌘⇧4.
            if current == .screenshot,
               flags.contains(.maskCommand),
               !ignoring.contains(.maskCommand) {
                return .none
            }
            return current
        }
        if suppressed { return .none }
        let alone = flags.intersection(watchedFlags).subtracting(ignoring)
        if alone == bindings.screenshot.eventFlag { return .screenshot }
        if let annotate = bindings.annotate, alone == annotate.eventFlag { return .annotate }
        return .none
    }

    /// Typing suppresses holds until every session key is up, so a capital letter
    /// never leaves screenshot mode on.
    static func stillSuppressed(after flags: CGEventFlags, bindings: Bindings) -> Bool {
        !flags.intersection(bindings.flags).isEmpty
    }

    /// A key press that reaches the app ends the hold, unless a grab or stroke is
    /// moving. Marks already drawn are saved, the same as releasing the key.
    static func keyEndsHold(_ hold: Hold, gestureInProgress: Bool) -> Bool {
        hold != .none && !gestureInProgress
    }

    enum Press: Equatable {
        /// The app underneath receives the click.
        case passThrough
        /// A drag grabs the screen. A press that does not move is replayed with its flags.
        case select
        /// Text places a label right away.
        case draw
        /// A drag draws. A press that does not move is replayed with its flags (⌃-click).
        case drawOrClick
    }

    static func press(hold: Hold, mode: MarkupMode, tool: AnnotationTool, editing: Bool) -> Press {
        if editing || hold == .none { return .passThrough }
        if mode == .capture { return .select }
        return tool == .text ? .draw : .drawOrClick
    }

    enum Edge: Equatable {
        /// A text label is open. The key only changes a letter.
        case keepEditing
        /// A grab or a stroke is already moving. Leave it alone.
        case keepGesture
        /// Crosshair on, markup bar on with the camera selected.
        case beginScreenshot
        /// Tool cursor on, markup bar on with the tool selected.
        case beginAnnotate
        /// The key came up mid-gesture. The mouse-up finishes it.
        case finishGestureOnRelease
        /// The key came up with nothing moving. Save marks and go back to normal clicks.
        case endHold
    }

    static func edge(to hold: Hold, editing: Bool, gestureInProgress: Bool) -> Edge {
        if editing { return .keepEditing }
        switch hold {
        case .screenshot:
            return gestureInProgress ? .keepGesture : .beginScreenshot
        case .annotate:
            return gestureInProgress ? .keepGesture : .beginAnnotate
        case .none:
            return gestureInProgress ? .finishGestureOnRelease : .endHold
        }
    }

    /// Points the pointer must travel before a ⌃-press becomes a stroke.
    static let drawThreshold: CGFloat = 3
}
