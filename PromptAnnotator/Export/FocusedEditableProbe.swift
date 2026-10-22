import AppKit
import ApplicationServices

/// Whether the frontmost focused UI looks like a text insertion target.
enum FocusPasteTarget: Equatable, Sendable {
    /// AX role / attributes clearly indicate an editable text control.
    case editable
    /// Focused element is clearly not a text field (button, static text, …).
    case notEditable
    /// Ambiguous (web view, Electron, unknown role). Treat as pasteable so we
    /// do not break apps where auto-paste already works.
    case unknown
}

enum FocusPasteAction: Equatable, Sendable {
    /// Fire the synthetic ⌘V delivery now.
    case autoPaste
    /// Leave output staged; do not synthesize paste; show a ready-to-paste hint.
    case holdPending
    /// Skip delivery entirely (paste-on-stop off, onboarding skip, empty).
    case skip
}

enum FocusPasteDecision {
    /// Pure decision for session-end paste. Unit-tested without AX.
    static func action(
        target: FocusPasteTarget,
        pasteOnStop: Bool,
        settingsFocused: Bool,
        skipPaste: Bool,
        hasOutput: Bool
    ) -> FocusPasteAction {
        if skipPaste || !pasteOnStop || !hasOutput { return .skip }
        if settingsFocused { return .holdPending }
        switch target {
        case .editable, .unknown:
            return .autoPaste
        case .notEditable:
            return .holdPending
        }
    }
}

protocol FocusedEditableProbing: Sendable {
    func classifyFocusedElement() -> FocusPasteTarget
}

/// Live Accessibility probe. Conservative: only returns `.notEditable` when sure.
struct SystemFocusedEditableProbe: FocusedEditableProbing {
    func classifyFocusedElement() -> FocusPasteTarget {
        // Without trust we cannot read focus — keep current auto-paste behavior.
        guard AXIsProcessTrusted() else { return .unknown }

        let system = AXUIElementCreateSystemWide()
        var focusedRef: CFTypeRef?
        let status = AXUIElementCopyAttributeValue(
            system,
            kAXFocusedUIElementAttribute as CFString,
            &focusedRef
        )
        guard status == .success, let focusedRef else {
            return .notEditable
        }
        let element = unsafeBitCast(focusedRef, to: AXUIElement.self)
        return Self.classify(element)
    }

    /// Exposed for tests with a hand-built role/attribute snapshot.
    static func classify(
        role: String?,
        valueSettable: Bool?,
        hasSelectedTextRange: Bool,
        editableFlag: Bool?
    ) -> FocusPasteTarget {
        let role = role ?? ""

        let editableRoles: Set<String> = [
            "AXTextField",
            "AXTextArea",
            "AXComboBox",
            "AXSearchField",
        ]
        if editableRoles.contains(role) { return .editable }
        if editableFlag == true { return .editable }
        if hasSelectedTextRange { return .editable }

        // Value is settable on text fields *and* sliders/steppers — require a text-ish role.
        if valueSettable == true {
            let lower = role.lowercased()
            if lower.contains("text") || lower.contains("field") || lower.contains("edit") {
                return .editable
            }
        }

        let notEditableRoles: Set<String> = [
            "AXButton",
            "AXCheckBox",
            "AXRadioButton",
            "AXStaticText",
            "AXImage",
            "AXMenuItem",
            "AXMenuBarItem",
            "AXMenuBar",
            "AXMenu",
            "AXToolbar",
            "AXTabGroup",
            "AXProgressIndicator",
            "AXSlider",
            "AXPopUpButton",
            "AXDisclosureTriangle",
            "AXWindow",
            "AXApplication",
            "AXSplitGroup",
            "AXGrowArea",
            "AXValueIndicator",
            "AXBusyIndicator",
            "AXColorWell",
            "AXLevelIndicator",
            "AXHandle",
            "AXIncrementor",
            "AXDecrementArrow",
            "AXIncrementArrow",
        ]
        if notEditableRoles.contains(role) { return .notEditable }

        // Web areas, groups, scroll areas, lists, unknown — leave alone.
        return .unknown
    }

    private static func classify(_ element: AXUIElement) -> FocusPasteTarget {
        let role = stringValue(element, kAXRoleAttribute as CFString)
        let editableFlag = boolValue(element, "AXEditable" as CFString)
        let valueSettable = isSettable(element, kAXValueAttribute as CFString)
        let hasRange = hasAttribute(element, kAXSelectedTextRangeAttribute as CFString)
        return classify(
            role: role,
            valueSettable: valueSettable,
            hasSelectedTextRange: hasRange,
            editableFlag: editableFlag
        )
    }

    private static func stringValue(_ element: AXUIElement, _ attribute: CFString) -> String? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute, &ref) == .success,
              let ref else { return nil }
        return (ref as? String) ?? (ref as? NSString) as String?
    }

    private static func boolValue(_ element: AXUIElement, _ attribute: CFString) -> Bool? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute, &ref) == .success,
              let ref else { return nil }
        if let number = ref as? NSNumber { return number.boolValue }
        if CFGetTypeID(ref) == CFBooleanGetTypeID() {
            return CFEqual(ref, kCFBooleanTrue)
        }
        return nil
    }

    private static func isSettable(_ element: AXUIElement, _ attribute: CFString) -> Bool? {
        var settable: DarwinBoolean = false
        let status = AXUIElementIsAttributeSettable(element, attribute, &settable)
        guard status == .success else { return nil }
        return settable.boolValue
    }

    private static func hasAttribute(_ element: AXUIElement, _ attribute: CFString) -> Bool {
        var ref: CFTypeRef?
        return AXUIElementCopyAttributeValue(element, attribute, &ref) == .success && ref != nil
    }
}
