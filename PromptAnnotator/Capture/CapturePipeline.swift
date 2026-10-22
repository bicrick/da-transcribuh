import CoreGraphics
import Foundation

/// Off-MainActor capture → crop → encode for the recording snip path.
/// Priorities: audio stays real-time; this work is `.userInitiated` at the call site;
/// PNG encode uses `.utility` inside `PNG.writeAsync`.
enum CapturePipeline {
    static func captureAndEncode(
        displayID: CGDirectDisplayID,
        pointSize: CGSize,
        shapes: [AnnotationShape],
        excludedWindowIDs: [CGWindowID],
        crop: CGRect?,
        url: URL
    ) async throws -> CGImage {
        let captured = try await DisplayCapture.capture(
            displayID: displayID,
            pointSize: pointSize,
            shapes: shapes,
            excludedWindowIDs: excludedWindowIDs,
            sourceRect: crop
        )
        let image: CGImage
        if let crop, !shapes.isEmpty {
            // Marks live in full-display space: composite full frame, then crop.
            guard let cropped = CapturePerf.interval(.crop, {
                RegionCrop.crop(captured, selection: crop, pointSize: pointSize)
            }) else {
                throw ExportError("The selection was too small to capture.")
            }
            image = cropped
        } else {
            // Clean region snip already used `sourceRect`; annotate / full-frame as-captured.
            image = captured
        }
        try await PNG.writeAsync(image, to: url)
        return image
    }
}
