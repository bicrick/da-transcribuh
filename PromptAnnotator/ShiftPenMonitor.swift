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

/// Watches Shift and the pointer while another app is focused.
/// The overlay window itself stays click-through. This tap captures the pointer
/// only while Shift is held, and it lets the recording island and markup bar
/// receive the click either way.
@MainActor
final class ShiftPenMonitor {
    weak var session: SessionController?

    private(set) var isSwallowingMouse = false
    private var shiftDown = false
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var active = false

    func install() -> Bool {
        guard tap == nil else { return true }
        let info = Unmanaged.passUnretained(self).toOpaque()
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: Self.eventMask,
            callback: { _, type, event, userInfo in
                guard let userInfo else { return Unmanaged.passUnretained(event) }
                let monitor = Unmanaged<ShiftPenMonitor>.fromOpaque(userInfo).takeUnretainedValue()
                guard Thread.isMainThread else {
                    return Unmanaged.passUnretained(event)
                }
                return MainActor.assumeIsolated {
                    monitor.handle(type: type, event: event)
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
        isSwallowingMouse = false
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

    func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            return Unmanaged.passUnretained(event)
        }
        guard active, let session else {
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
            if shiftDown || isSwallowingMouse {
                updateCursor(session: session)
            }
            return Unmanaged.passUnretained(event)

        case .leftMouseDown:
            if overChrome(event) {
                return Unmanaged.passUnretained(event)
            }
            guard shiftDown, let local = location(of: event) else {
                return Unmanaged.passUnretained(event)
            }
            isSwallowingMouse = true
            session.penMouseDown(at: local.point, display: local.display)
            updateCursor(session: session)
            return nil

        case .leftMouseDragged:
            guard isSwallowingMouse, let local = location(of: event) else {
                return Unmanaged.passUnretained(event)
            }
            session.penMouseDrag(at: local.point, display: local.display)
            return nil

        case .leftMouseUp:
            guard isSwallowingMouse else {
                return Unmanaged.passUnretained(event)
            }
            isSwallowingMouse = false
            if let local = location(of: event) {
                session.penMouseUp(at: local.point, display: local.display)
            }
            if !shiftDown {
                NSCursor.arrow.set()
            }
            return nil

        case .keyDown:
            return handleKey(event, session: session)

        default:
            return Unmanaged.passUnretained(event)
        }
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
        if session.penKeyPolicy() == .editing {
            NSCursor.iBeam.set()
            return
        }
        guard shiftDown || isSwallowingMouse else { return }
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
