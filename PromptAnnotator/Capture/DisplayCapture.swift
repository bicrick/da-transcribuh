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

        let excludedIDs = Set(excludedWindowIDs)
        let excludedWindows = content.windows.filter { excludedIDs.contains($0.windowID) }
        let bundleID = Bundle.main.bundleIdentifier
        let ourApps = content.applications.filter { $0.bundleIdentifier == bundleID }

        let filter: SCContentFilter
        if !ourApps.isEmpty {
            filter = SCContentFilter(
                display: display,
                excludingApplications: ourApps,
                exceptingWindows: []
            )
        } else {
            filter = SCContentFilter(display: display, excludingWindows: excludedWindows)
        }

        let configuration = SCStreamConfiguration()
        configuration.width = display.width
        configuration.height = display.height
        configuration.showsCursor = false
        configuration.capturesAudio = false
        configuration.scalesToFit = false

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
