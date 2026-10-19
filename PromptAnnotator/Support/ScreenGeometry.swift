import AppKit

enum ScreenGeometry {
    static var primaryHeight: CGFloat {
        NSScreen.screens.first?.frame.height ?? 0
    }

    /// Quartz global points (origin at the top-left of the primary display, y down)
    /// to AppKit screen points (origin at the bottom-left of the primary display, y up).
    static func appKitPoint(fromQuartz point: CGPoint) -> CGPoint {
        CGPoint(x: point.x, y: primaryHeight - point.y)
    }

    static func screen(containingAppKitPoint point: CGPoint) -> NSScreen? {
        NSScreen.screens.first { NSMouseInRect(point, $0.frame, false) }
    }

    /// Display-local point with the origin at the top-left of `screen` and y down.
    static func displayLocal(appKitPoint: CGPoint, screen: NSScreen) -> CGPoint {
        CGPoint(
            x: appKitPoint.x - screen.frame.minX,
            y: screen.frame.maxY - appKitPoint.y
        )
    }

    static func displayID(of screen: NSScreen) -> CGDirectDisplayID? {
        guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
            return nil
        }
        return CGDirectDisplayID(number.uint32Value)
    }

    static func screen(for displayID: CGDirectDisplayID) -> NSScreen? {
        NSScreen.screens.first { screen in
            self.displayID(of: screen) == displayID
        }
    }

    static func screenUnderMouse() -> NSScreen? {
        let mouse = NSEvent.mouseLocation
        return screen(containingAppKitPoint: mouse) ?? NSScreen.main ?? NSScreen.screens.first
    }
}
