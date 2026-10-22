import AppKit
import ScreenCaptureKit

enum DisplayCapture {
    /// Captures a display (or a point-space `sourceRect` on it), composites marks, and returns pixels.
    ///
    /// - Parameters:
    ///   - sourceRect: Optional selection in display-local points (origin top-left, y down).
    ///     When set and there are no shapes, only that region is captured via
    ///     `SCStreamConfiguration.sourceRect` — no full-Retina grab + crop.
    ///   - shapes: Marks in display-local points. When non-empty, the full display is
    ///     captured so strokes outside a selection still bake correctly, then composited.
    static func capture(
        displayID: CGDirectDisplayID,
        pointSize: CGSize,
        shapes: [AnnotationShape],
        excludedWindowIDs: [CGWindowID],
        sourceRect: CGRect? = nil
    ) async throws -> CGImage {
        ShareableContentCacheWatcher.installIfNeeded()
        return try await CapturePerf.intervalAsync(.capture) {
            try await captureBody(
                displayID: displayID,
                pointSize: pointSize,
                shapes: shapes,
                excludedWindowIDs: excludedWindowIDs,
                sourceRect: sourceRect
            )
        }
    }

    private static func captureBody(
        displayID: CGDirectDisplayID,
        pointSize: CGSize,
        shapes: [AnnotationShape],
        excludedWindowIDs: [CGWindowID],
        sourceRect: CGRect?
    ) async throws -> CGImage {
        let content = try await ShareableContentCache.shared.content()
        guard let display = content.displays.first(where: { $0.displayID == displayID }) else {
            // Display list may be stale after a cable pull — refresh once.
            await ShareableContentCache.shared.invalidate()
            let fresh = try await ShareableContentCache.shared.content(forceRefresh: true)
            guard let retry = fresh.displays.first(where: { $0.displayID == displayID }) else {
                throw ExportError("The display being marked is no longer available.")
            }
            return try await captureOnDisplay(
                display: retry,
                content: fresh,
                pointSize: pointSize,
                shapes: shapes,
                excludedWindowIDs: excludedWindowIDs,
                sourceRect: sourceRect
            )
        }
        return try await captureOnDisplay(
            display: display,
            content: content,
            pointSize: pointSize,
            shapes: shapes,
            excludedWindowIDs: excludedWindowIDs,
            sourceRect: sourceRect
        )
    }

    private static func captureOnDisplay(
        display: SCDisplay,
        content: SCShareableContent,
        pointSize: CGSize,
        shapes: [AnnotationShape],
        excludedWindowIDs: [CGWindowID],
        sourceRect: CGRect?
    ) async throws -> CGImage {
        // Capture the display as it is stacked: the front window, sheets, popovers,
        // and the menu bar. Excluding this app punched those windows out and left
        // whatever sat behind them. Only the recording chrome is left out.
        let excludedIDs = Set(excludedWindowIDs)
        let excludedWindows = content.windows.filter { excludedIDs.contains($0.windowID) }
        let filter = SCContentFilter(display: display, excludingWindows: excludedWindows)
        if #available(macOS 14.2, *) {
            filter.includeMenuBar = true
        }

        let significant = shapes.filter { $0.isSignificant() }
        // Marks are authored in full-display space — always grab the whole display when baking them.
        let regionOnly = significant.isEmpty ? sourceRect?.standardized : nil
        let configuration = makeConfiguration(
            display: display,
            filter: filter,
            sourceRect: regionOnly
        )

        let screenshot = try await CapturePerf.intervalAsync(.screenshot) {
            try await SCScreenshotManager.captureImage(
                contentFilter: filter,
                configuration: configuration
            )
        }

        if significant.isEmpty {
            // Region snip (or clean full-frame fallback): no composite allocation.
            return screenshot
        }

        let size = pointSize == .zero
            ? CGSize(width: screenshot.width, height: screenshot.height)
            : pointSize
        guard let composited = CapturePerf.interval(.composite, {
            ShapeRenderer.composite(base: screenshot, shapes: significant, pointSize: size)
        }) else {
            throw ExportError("Couldn't composite the marks onto the screenshot.")
        }
        return composited
    }

    private static func makeConfiguration(
        display: SCDisplay,
        filter: SCContentFilter,
        sourceRect: CGRect?
    ) -> SCStreamConfiguration {
        let configuration = SCStreamConfiguration()
        configuration.showsCursor = false
        configuration.capturesAudio = false
        configuration.scalesToFit = false
        if #available(macOS 14.0, *) {
            configuration.captureResolution = .best
        }
        if #available(macOS 14.2, *) {
            configuration.includeChildWindows = true
        }

        let scale = CGFloat(filter.pointPixelScale)
        if let box = sourceRect, box.width >= 1, box.height >= 1 {
            // Display-local points, origin top-left (matches our selection / shape space).
            configuration.sourceRect = box
            configuration.width = max(1, Int((box.width * scale).rounded()))
            configuration.height = max(1, Int((box.height * scale).rounded()))
        } else {
            // Prefer filter metrics when available so Retina scale matches the stream.
            let content = filter.contentRect
            if content.width > 0, content.height > 0, scale > 0 {
                configuration.width = max(1, Int((content.width * scale).rounded()))
                configuration.height = max(1, Int((content.height * scale).rounded()))
            } else {
                configuration.width = display.width
                configuration.height = display.height
            }
        }
        return configuration
    }
}
