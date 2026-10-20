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

/// Watches the pointer while another app is focused.
/// The overlay stays click-through. In capture mode a drag snippets the screen and a
/// click is replayed to the page. In annotate mode the tap captures the pointer only
/// while Shift is held. The recording island and markup bar receive the click either way.
@MainActor
final class ShiftPenMonitor {
    weak var session: SessionController?

    private struct PressedClick {
        var local: CGPoint
        var display: CGDirectDisplayID
    }

    private enum PointerHold {
        case idle
        case pending(PressedClick)
        case capturing(PressedClick)
        case drawing
    }

    private var shiftDown = false
    private var hold: PointerHold = .idle
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

    var shiftIsDown: Bool { shiftDown }

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
                let monitor = Unmanaged<ShiftPenMonitor>.fromOpaque(userInfo).takeUnretainedValue()
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
        return true
    }

    func stop() {
        active = false
        shiftDown = false
        hold = .idle
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
            NSCursor.arrow.set()
        case .drawing, .idle:
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
            let down = event.flags.contains(.maskShift)
            if down != shiftDown {
                shiftDown = down
                session.penShift(down: down)
                updateCursor(session: session)
            }
            return Unmanaged.passUnretained(event)

        case .mouseMoved:
            if shiftDown || isAnnotating {
                updateCursor(session: session)
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
            return handleKey(event, session: session)

        default:
            return Unmanaged.passUnretained(event)
        }
    }

    private func handleLeftDown(_ event: CGEvent, session: SessionController) -> Unmanaged<CGEvent>? {
        if discardUntilLeftUp {
            return nil
        }
        if overChrome(event) {
            return Unmanaged.passUnretained(event)
        }
        guard let local = location(of: event) else {
            return Unmanaged.passUnretained(event)
        }

        if session.markupMode == .capture {
            hold = .pending(PressedClick(local: local.point, display: local.display))
            return nil
        }

        guard session.markupMode == .annotate, shiftDown else {
            return Unmanaged.passUnretained(event)
        }
        hold = .drawing
        session.penMouseDown(at: local.point, display: local.display)
        updateCursor(session: session)
        return nil
    }

    private func handleLeftDragged(_ event: CGEvent, session: SessionController) -> Unmanaged<CGEvent>? {
        if discardUntilLeftUp {
            return nil
        }
        switch hold {
        case .pending(let press):
            guard let local = location(of: event) else { return nil }
            guard local.display == press.display else { return nil }
            if CaptureGesture.isDrag(from: press.local, to: local.point) {
                hold = .capturing(press)
                session.captureDragBegan(origin: press.local, current: local.point, display: press.display)
                NSCursor.crosshair.set()
            }
            return nil
        case .capturing(let press):
            guard let local = location(of: event), local.display == press.display else { return nil }
            session.captureDragMoved(origin: press.local, current: local.point, display: press.display)
            NSCursor.crosshair.set()
            return nil
        case .drawing:
            guard let local = location(of: event) else { return nil }
            session.penMouseDrag(at: local.point, display: local.display)
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
            return nil
        }
        switch hold {
        case .pending(let press):
            hold = .idle
            let local = location(of: event)
            let movedToAnotherDisplay = local.map { $0.display != press.display } ?? false
            let dragged = local.map { CaptureGesture.isDrag(from: press.local, to: $0.point) } ?? false
            if !movedToAnotherDisplay, !dragged {
                replayClick(event, proxy: proxy)
            }
            return nil
        case .capturing(let press):
            hold = .idle
            NSCursor.arrow.set()
            if let local = location(of: event), local.display == press.display {
                session.captureDragEnded(origin: press.local, current: local.point, display: press.display)
            } else {
                session.captureDragCancelled()
            }
            return nil
        case .drawing:
            hold = .idle
            if let local = location(of: event) {
                session.penMouseUp(at: local.point, display: local.display)
            }
            if !shiftDown {
                NSCursor.arrow.set()
            }
            return nil
        case .idle:
            return Unmanaged.passUnretained(event)
        }
    }

    /// Posts the swallowed press just downstream of this tap, so the page receives a
    /// click and this tap does not see it as a new press.
    private func replayClick(_ event: CGEvent, proxy: CGEventTapProxy) {
        let point = event.location
        let flags = event.flags
        let clickState = max(event.getIntegerValueField(.mouseEventClickState), 1)
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
            NSCursor.arrow.set()
            session.captureDragCancelled()
            return true
        case .drawing, .idle:
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

    private func updateCursor(session: SessionController) {
        if case .capturing = hold {
            NSCursor.crosshair.set()
            return
        }
        if session.penKeyPolicy() == .editing {
            NSCursor.iBeam.set()
            return
        }
        guard session.markupMode == .annotate, shiftDown || isAnnotating else { return }
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
        guard length > 0 else { return nil }
        return String(utf16CodeUnits: buffer, count: length)
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
}
