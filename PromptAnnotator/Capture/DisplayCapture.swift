import AppKit
import ScreenCaptureKit

enum DisplayCapture {
    static func capture(
        displayID: CGDirectDisplayID,
        pointSize: CGSize,
        shapes: [AnnotationShape],
        excludedWindowIDs: [CGWindowID]
    ) async throws -> CGImage {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let display = content.displays.first(where: { $0.displayID == displayID }) else {
            throw ExportError("The display being marked is no longer available.")
        }

        // Capture the display as it is stacked: the front window, sheets, popovers,
        // and the menu bar. Excluding this app punched those windows out and left
        // whatever sat behind them. Only the recording chrome is left out.
        let excludedIDs = Set(excludedWindowIDs)
        let excludedWindows = content.windows.filter { excludedIDs.contains($0.windowID) }
        let filter = SCContentFilter(display: display, excludingWindows: excludedWindows)
        if #available(macOS 14.2, *) {
            filter.includeMenuBar = true
        }

        let configuration = SCStreamConfiguration()
        configuration.width = display.width
        configuration.height = display.height
        configuration.showsCursor = false
        configuration.capturesAudio = false
        configuration.scalesToFit = false
        if #available(macOS 14.2, *) {
            configuration.includeChildWindows = true
        }

        let screenshot = try await SCScreenshotManager.captureImage(
            contentFilter: filter,
            configuration: configuration
        )
        let size = pointSize == .zero
            ? CGSize(width: screenshot.width, height: screenshot.height)
            : pointSize
        guard let composited = ShapeRenderer.composite(base: screenshot, shapes: shapes, pointSize: size) else {
            throw ExportError("Couldn't composite the marks onto the screenshot.")
        }
        return composited
    }
}
