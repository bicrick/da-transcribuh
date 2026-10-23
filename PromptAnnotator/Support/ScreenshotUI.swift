import AppKit
import CoreGraphics

/// Detects the macOS screenshot UI (⌘⇧3/4/5, the ⌘⇧5 toolbar, window-pick mode).
/// The clipboard panel used to read that UI taking focus or a crosshair click as
/// "the user went elsewhere" and closed before the shot was taken.
enum ScreenshotUI {
    /// Processes that draw the screenshot crosshair, toolbar and thumbnail.
    static let ownerNames: Set<String> = ["screencaptureui", "screencapture", "Screenshot"]
    static let bundleIDs: Set<String> = [
        "com.apple.screencaptureui",
        "com.apple.screenshot.launcher",
        "com.apple.Screenshot",
    ]

    /// Window owner names are readable without Screen Recording permission.
    static func windows() -> [[String: Any]] {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
            as? [[String: Any]] else { return [] }
        return list.filter { info in
            guard let owner = info[kCGWindowOwnerName as String] as? String else { return false }
            return ownerNames.contains(owner)
        }
    }

    static func isFrontmost(_ app: NSRunningApplication?) -> Bool {
        guard let id = app?.bundleIdentifier else { return false }
        return bundleIDs.contains(id)
    }

    /// Any screenshot UI on screen, or the Screenshot app in front.
    static func isActive() -> Bool {
        isFrontmost(NSWorkspace.shared.frontmostApplication) || !windows().isEmpty
    }

    /// True when a screenshot window covers this point (AppKit screen coordinates).
    /// The crosshair overlay covers the whole screen, the post-shot thumbnail only
    /// its corner, so a normal click elsewhere after a shot still dismisses.
    static func covers(_ point: NSPoint) -> Bool {
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        let cgPoint = CGPoint(x: point.x, y: primaryHeight - point.y)
        return windows().contains { info in
            guard let dict = info[kCGWindowBounds as String] as? NSDictionary,
                  let rect = CGRect(dictionaryRepresentation: dict as CFDictionary) else { return false }
            return rect.contains(cgPoint)
        }
    }
}
