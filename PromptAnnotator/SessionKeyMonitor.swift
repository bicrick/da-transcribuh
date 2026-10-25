import AppKit
import CoreGraphics

enum PenKey: Equatable {
    case character(String)
    case backspace
    case escape
    case submit
    case undo
    case redo
}

enum KeyPolicy: Equatable {
    case passThrough
    case drawing
    case editing
}

/// Watches the keyboard and pointer while another app is focused.
/// The overlay stays click-through and plain clicks and drags always reach the app.
/// Holding the screenshot key alone (Shift by default) arms a crosshair: a drag grabs
/// the screen and a click that does not move is replayed with its flags. Holding the
/// annotate key alone (Control by default) draws with the armed tool, and a ⌃-click
/// that does not move is replayed as a normal ⌃-click. Any other key press ends an
/// idle hold, so typing a capital letter never leaves the crosshair on.
/// The recording island and markup bar receive the click either way.
@MainActor
final class SessionKeyMonitor {
    weak var session: SessionController?

    private struct PressedClick {
        var local: CGPoint
        var display: CGDirectDisplayID
        var flags: CGEventFlags
        var clickState: Int64
    }

    private enum PointerHold {
        case idle
        /// Screenshot press waiting to become a grab or a click.
        case pending(PressedClick)
        case capturing(PressedClick)
        /// Annotate press waiting to become a stroke or a click.
        case pendingDraw(PressedClick)
        case drawing
    }

    private var keyHold: SessionKeys.Hold = .none
    /// Set by typing. No hold starts until every session key is up again.
    private var suppressed = false
    /// Coalesces hold delivery so AppKit/SwiftUI work runs after the CGEvent tap returns.
    private var holdDeliveryScheduled = false
    private var hold: PointerHold = .idle
    private var chromePress: PressedClick?
    private var discardUntilLeftUp = false
    private var isReplaying = false
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var active = false

    var isSwallowingMouse: Bool {
        if case .idle = hold { return false }
        return true
    }

    var isAnnotating: Bool {
        if case .drawing = hold { return true }
        return false
    }

    var isCapturing: Bool {
        switch hold {
        case .pending, .capturing: return true
        default: return false
        }
    }

    /// A session key is held: the crosshair or a tool is armed.
    var holdIsActive: Bool { keyHold != .none }

    var currentHold: SessionKeys.Hold { keyHold }

    func install() -> Bool {
        guard tap == nil else { return true }
        let info = Unmanaged.passUnretained(self).toOpaque()
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: Self.eventMask,
            callback: { proxy, type, event, userInfo in
                guard let userInfo else { return Unmanaged.passUnretained(event) }
                let monitor = Unmanaged<SessionKeyMonitor>.fromOpaque(userInfo).takeUnretainedValue()
                guard Thread.isMainThread else {
                    return Unmanaged.passUnretained(event)
                }
                return MainActor.assumeIsolated {
                    monitor.handle(proxy: proxy, type: type, event: event)
                }
            },
            userInfo: info
        ) else {
            return false
        }

        self.tap = tap
        active = true
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        self.source = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        // A key already held when the session starts (push to talk plus Shift) counts.
        applyFlags(CGEventSource.flagsState(.combinedSessionState))
        return true
    }

    func stop() {
        active = false
        keyHold = .none
        suppressed = false
        holdDeliveryScheduled = false
        hold = .idle
        chromePress = nil
        discardUntilLeftUp = false
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let source {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        tap = nil
        source = nil
        NSCursor.arrow.set()
    }

    /// Drops a capture press so a mode change does not turn the release into a second click.
    func cancelHold() {
        switch hold {
        case .pending, .capturing:
            discardUntilLeftUp = true
            hold = .idle
        case .pendingDraw, .drawing, .idle:
            break
        }
    }

    func handle(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            return Unmanaged.passUnretained(event)
        }
        guard active, let session else {
            return Unmanaged.passUnretained(event)
        }
        if isLeftMouse(type), isReplay(event) {
            return Unmanaged.passUnretained(event)
        }

        switch type {
        case .flagsChanged:
            applyFlags(event.flags)
            return Unmanaged.passUnretained(event)

        case .mouseMoved:
            if keyHold != .none || isAnnotating {
                updateCursor(session: session)
                if keyHold == .screenshot, let local = location(of: event) {
                    session.screenshotPointerMoved(to: local.point, display: local.display)
                }
            }
            return Unmanaged.passUnretained(event)

        case .leftMouseDown:
            return handleLeftDown(event, session: session)

        case .leftMouseDragged:
            return handleLeftDragged(event, session: session)

        case .leftMouseUp:
            return handleLeftUp(event, session: session, proxy: proxy)

        case .keyDown:
            if isEscape(event), cancelCapture(session: session) {
                return nil
            }
            let result = handleKey(event, session: session)
            if result != nil {
                endHoldForTyping()
            }
            return result

        default:
            return Unmanaged.passUnretained(event)
        }
    }

    private func handleLeftDown(_ event: CGEvent, session: SessionController) -> Unmanaged<CGEvent>? {
        if discardUntilLeftUp {
            return nil
        }
        guard let local = location(of: event) else {
            chromePress = nil
            return Unmanaged.passUnretained(event)
        }
        let press = PressedClick(
            local: local.point,
            display: local.display,
            flags: event.flags,
            clickState: max(event.getIntegerValueField(.mouseEventClickState), 1)
        )
        if overChrome(event) {
            chromePress = press
            return Unmanaged.passUnretained(event)
        }
        chromePress = nil

        switch SessionKeys.press(
            hold: keyHold,
            mode: session.markupMode,
            tool: session.penTool(),
            editing: session.penKeyPolicy() == .editing
        ) {
        case .passThrough:
            return Unmanaged.passUnretained(event)
        case .select:
            hold = .pending(press)
            return nil
        case .draw:
            hold = .drawing
            session.penMouseDown(at: local.point, display: local.display)
            updateCursor(session: session)
            return nil
        case .drawOrClick:
            hold = .pendingDraw(press)
            return nil
        }
    }

    private func handleLeftDragged(_ event: CGEvent, session: SessionController) -> Unmanaged<CGEvent>? {
        if discardUntilLeftUp {
            return nil
        }
        if case .idle = hold, let press = chromePress, keyHold == .screenshot, session.markupMode == .capture {
            guard let local = location(of: event), local.display == press.display else {
                return Unmanaged.passUnretained(event)
            }
            let moved = CaptureGesture.isDrag(from: press.local, to: local.point)
            if moved, !overChrome(event) {
                let start = PressedClick(local: local.point, display: local.display, flags: press.flags, clickState: 1)
                hold = .capturing(start)
                chromePress = nil
                session.captureDragBegan(origin: start.local, current: start.local, display: start.display)
                ScreenshotCursor.cursor.set()
                return nil
            }
            return Unmanaged.passUnretained(event)
        }
        switch hold {
        case .pending(let press):
            guard let local = location(of: event) else { return nil }
            guard local.display == press.display else { return nil }
            if CaptureGesture.isDrag(from: press.local, to: local.point) {
                hold = .capturing(press)
                session.captureDragBegan(origin: press.local, current: local.point, display: press.display)
                ScreenshotCursor.cursor.set()
            }
            return nil
        case .capturing(let press):
            guard let local = location(of: event), local.display == press.display else { return nil }
            session.captureDragMoved(origin: press.local, current: local.point, display: press.display)
            ScreenshotCursor.cursor.set()
            return nil
        case .pendingDraw(let press):
            guard let local = location(of: event), local.display == press.display else { return nil }
            let travel = hypot(local.point.x - press.local.x, local.point.y - press.local.y)
            if travel >= SessionKeys.drawThreshold {
                hold = .drawing
                session.penMouseDown(at: press.local, display: press.display)
                session.penMouseDrag(at: local.point, display: local.display)
                updateCursor(session: session)
            }
            return nil
        case .drawing:
            guard let local = location(of: event) else { return nil }
            session.penMouseDrag(at: local.point, display: local.display)
            updateCursor(session: session)
            return nil
        case .idle:
            return Unmanaged.passUnretained(event)
        }
    }

    private func handleLeftUp(
        _ event: CGEvent,
        session: SessionController,
        proxy: CGEventTapProxy
    ) -> Unmanaged<CGEvent>? {
        if discardUntilLeftUp {
            discardUntilLeftUp = false
            chromePress = nil
            return nil
        }
        chromePress = nil
        switch hold {
        case .pending(let press):
            hold = .idle
            let local = location(of: event)
            let movedToAnotherDisplay = local.map { $0.display != press.display } ?? false
            let dragged = local.map { CaptureGesture.isDrag(from: press.local, to: $0.point) } ?? false
            if !movedToAnotherDisplay, !dragged {
                replayClick(press, at: event.location, proxy: proxy)
            }
            afterGesture(session: session)
            return nil
        case .capturing(let press):
            hold = .idle
            if let local = location(of: event), local.display == press.display {
                session.captureDragEnded(origin: press.local, current: local.point, display: press.display)
            } else {
                session.captureDragCancelled()
            }
            afterGesture(session: session)
            return nil
        case .pendingDraw(let press):
            hold = .idle
            replayClick(press, at: event.location, proxy: proxy)
            afterGesture(session: session)
            return nil
        case .drawing:
            hold = .idle
            if let local = location(of: event) {
                session.penMouseUp(at: local.point, display: local.display)
            }
            afterGesture(session: session)
            return nil
        case .idle:
            return Unmanaged.passUnretained(event)
        }
    }

    /// A gesture that outlived its key finishes here. Return to normal clicks.
    private func afterGesture(session: SessionController) {
        if keyHold == .none {
            session.sessionHoldGestureFinished()
            NSCursor.arrow.set()
        } else {
            updateCursor(session: session)
        }
    }

    /// Posts the swallowed press just downstream of this tap, so the page receives a
    /// click and this tap does not see it as a new press.
    private func replayClick(_ press: PressedClick, at point: CGPoint, proxy: CGEventTapProxy) {
        let flags = press.flags
        let clickState = press.clickState
        let source = CGEventSource(stateID: .hidSystemState)
        source?.localEventsSuppressionInterval = 0
        source?.userData = Self.replayToken
        guard let down = CGEvent(
            mouseEventSource: source,
            mouseType: .leftMouseDown,
            mouseCursorPosition: point,
            mouseButton: .left
        ), let up = CGEvent(
            mouseEventSource: source,
            mouseType: .leftMouseUp,
            mouseCursorPosition: point,
            mouseButton: .left
        ) else {
            return
        }
        down.flags = flags
        up.flags = flags
        down.setIntegerValueField(.mouseEventClickState, value: clickState)
        up.setIntegerValueField(.mouseEventClickState, value: clickState)
        down.setIntegerValueField(.eventSourceUserData, value: Self.replayToken)
        up.setIntegerValueField(.eventSourceUserData, value: Self.replayToken)
        isReplaying = true
        down.tapPostEvent(proxy)
        up.tapPostEvent(proxy)
        isReplaying = false
    }

    private func isLeftMouse(_ type: CGEventType) -> Bool {
        type == .leftMouseDown || type == .leftMouseDragged || type == .leftMouseUp
    }

    private func isReplay(_ event: CGEvent) -> Bool {
        isReplaying || event.getIntegerValueField(.eventSourceUserData) == Self.replayToken
    }

    private func cancelCapture(session: SessionController) -> Bool {
        switch hold {
        case .pending, .capturing:
            discardUntilLeftUp = true
            hold = .idle
            session.captureDragCancelled()
            afterGesture(session: session)
            return true
        case .pendingDraw, .drawing, .idle:
            return false
        }
    }

    private func isEscape(_ event: CGEvent) -> Bool {
        event.getIntegerValueField(.keyboardEventKeycode) == KeyCode.escape
            && !event.flags.contains(.maskCommand)
            && !event.flags.contains(.maskAlternate)
            && !event.flags.contains(.maskControl)
    }

    private func handleKey(_ event: CGEvent, session: SessionController) -> Unmanaged<CGEvent>? {
        let code = event.getIntegerValueField(.keyboardEventKeycode)
        let flags = event.flags
        let command = flags.contains(.maskCommand)
        let shift = flags.contains(.maskShift)

        switch session.penKeyPolicy() {
        case .passThrough:
            return Unmanaged.passUnretained(event)
        case .drawing:
            if code == KeyCode.escape {
                session.penKey(.escape)
                return nil
            }
            if command && code == KeyCode.z {
                session.penKey(shift ? .redo : .undo)
                return nil
            }
            return Unmanaged.passUnretained(event)
        case .editing:
            if code == KeyCode.escape {
                session.penKey(.escape)
                return nil
            }
            if code == KeyCode.return || code == KeyCode.keypadEnter {
                session.penKey(.submit)
                return nil
            }
            if code == KeyCode.delete || code == KeyCode.forwardDelete {
                session.penKey(.backspace)
                return nil
            }
            if command && code == KeyCode.v {
                let pasted = (NSPasteboard.general.string(forType: .string) ?? "")
                    .replacingOccurrences(of: "\n", with: " ")
                    .replacingOccurrences(of: "\r", with: " ")
                    .trimmingCharacters(in: .whitespaces)
                if !pasted.isEmpty {
                    session.penKey(.character(pasted))
                }
                return nil
            }
            if command {
                return nil
            }
            if let text = characters(in: event), text != "\r", text != "\n", !text.isEmpty {
                let printable = text.unicodeScalars.allSatisfy { scalar in
                    !CharacterSet.controlCharacters.contains(scalar) || scalar == " "
                }
                if printable {
                    session.penKey(.character(text))
                    return nil
                }
            }
            return nil
        }
    }

    /// Tracks the session keys from a modifier change. Session UI runs on the next
    /// main-queue turn, not inside the tap: it orders windows, updates @Published
    /// SwiftUI state, and may commit the canvas, all of which can raise AppKit
    /// exceptions when re-entered from a CGEvent tap.
    private func applyFlags(_ flags: CGEventFlags) {
        let bindings = AppSettings.shared.sessionKeys
        if suppressed {
            suppressed = SessionKeys.stillSuppressed(after: flags, bindings: bindings)
        }
        let next = SessionKeys.hold(
            after: flags,
            current: keyHold,
            bindings: bindings,
            ignoring: session?.heldChordFlags() ?? [],
            suppressed: suppressed
        )
        guard next != keyHold else { return }
        keyHold = next
        scheduleHoldDelivery()
    }

    /// Typing while a session key is down means the key was meant for a capital or a
    /// shortcut. Drop an idle hold and keep it off until the key comes up.
    private func endHoldForTyping() {
        guard SessionKeys.keyEndsHold(keyHold, gestureInProgress: isSwallowingMouse) else { return }
        keyHold = .none
        suppressed = true
        scheduleHoldDelivery()
    }

    /// Delivers the latest hold on the next main-queue turn, coalescing bursts.
    private func scheduleHoldDelivery() {
        guard !holdDeliveryScheduled else { return }
        holdDeliveryScheduled = true
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.holdDeliveryScheduled = false
                guard self.active, let session = self.session else { return }
                session.sessionHoldChanged(to: self.keyHold)
                self.updateCursor(session: session)
            }
        }
    }

    private func updateCursor(session: SessionController) {
        if case .capturing = hold {
            ScreenshotCursor.cursor.set()
            return
        }
        if session.penKeyPolicy() == .editing {
            NSCursor.iBeam.set()
            return
        }
        guard keyHold != .none || isAnnotating else {
            NSCursor.arrow.set()
            return
        }
        if session.markupMode == .capture {
            ScreenshotCursor.cursor.set()
            return
        }
        ToolCursors.cursor(for: session.penTool()).set()
    }

    private func overChrome(_ event: CGEvent) -> Bool {
        let point = ScreenGeometry.appKitPoint(fromQuartz: event.location)
        return session?.hitRects().contains { rect in
            rect.insetBy(dx: -8, dy: -8).contains(point)
        } ?? false
    }

    private func location(of event: CGEvent) -> (point: CGPoint, display: CGDirectDisplayID)? {
        let appKit = ScreenGeometry.appKitPoint(fromQuartz: event.location)
        guard let screen = ScreenGeometry.screen(containingAppKitPoint: appKit),
              let display = ScreenGeometry.displayID(of: screen) else {
            return nil
        }
        let local = ScreenGeometry.displayLocal(appKitPoint: appKit, screen: screen)
        return (local, display)
    }

    private func characters(in event: CGEvent) -> String? {
        var length = 0
        var buffer = [UniChar](repeating: 0, count: 8)
        event.keyboardGetUnicodeString(
            maxStringLength: 8,
            actualStringLength: &length,
            unicodeString: &buffer
        )
        if length > 0 {
            return String(utf16CodeUnits: buffer, count: length)
        }
        let typed = NSEvent(cgEvent: event)?.characters
        guard let typed, !typed.isEmpty else { return nil }
        return typed
    }

    private static let replayToken: Int64 = 0x5041_5265

    private static let eventMask: CGEventMask = {
        let types: [CGEventType] = [
            .leftMouseDown,
            .leftMouseDragged,
            .leftMouseUp,
            .mouseMoved,
            .flagsChanged,
            .keyDown,
            .tapDisabledByTimeout,
            .tapDisabledByUserInput,
        ]
        return types.reduce(0) { mask, type in
            mask | (1 << type.rawValue)
        }
    }()
}

private enum KeyCode {
    static let escape: Int64 = 53
    static let `return`: Int64 = 36
    static let keypadEnter: Int64 = 76
    static let delete: Int64 = 51
    static let forwardDelete: Int64 = 117
    static let z: Int64 = 6
    static let v: Int64 = 9
}
