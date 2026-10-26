import AppKit
import SwiftUI
import XCTest
@testable import PromptAnnotator

/// Offscreen renders of a linked take (collage + words) in the history list and its
/// preview. Skipped unless `DTShotRenderDir` is set. Temp store only; windows sit
/// far off screen at alpha 0 and never take focus.
@MainActor
final class ClipboardLinkedRowRenderTests: XCTestCase {
    private var folder: URL!

    override func tearDown() async throws {
        ClipboardHistoryStore.flushPendingWrites()
        if let folder { try? FileManager.default.removeItem(at: folder) }
    }

    func testRenderLinkedTakeRows() throws {
        guard let dir = ProcessInfo.processInfo.environment["DTShotRenderDir"], !dir.isEmpty else {
            throw XCTSkip("Set DTShotRenderDir to render the linked history row.")
        }
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        InkFontRegistrar.registerBundledFonts()
        folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("clipboard-linked-render-\(UUID().uuidString)", isDirectory: true)
        let store = ClipboardHistoryStore(folder: folder)
        store.historyLimitOverride = 50
        _ = store.ingest(payload: .text("npm run build -- --watch"), source: .pasteboard, applicationName: "Terminal")
        ClipboardHistoryController.ingestSession(
            transcript: nil, imagePNG: Self.collage(tiles: 1, seed: 3), into: store
        )
        ClipboardHistoryController.ingestSession(
            transcript: "this header wraps on small screens, keep it on one line",
            imagePNG: Self.collage(tiles: 2, seed: 1), into: store
        )
        _ = store.ingest(payload: .text("https://github.com/bicrick/da-transcribuh/pulls"),
                         source: .pasteboard, applicationName: "Safari")
        ClipboardHistoryController.ingestSession(
            transcript: "make these three buttons the same width and move the save button to the right",
            imagePNG: Self.collage(tiles: 3, seed: 2), into: store
        )
        let linked = try XCTUnwrap(store.items.first { $0.isLinkedSession })

        for (name, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
            NSApp.appearance = NSAppearance(named: appearance)
            let list = ClipboardHistoryView(store: store, onPick: { _, _ in }, onClose: {})
                .frame(width: ClipboardHistoryView.preferredSize.width,
                       height: ClipboardHistoryView.preferredSize.height)
                .background(Ink.window)
            try render(AnyView(list), size: ClipboardHistoryView.preferredSize,
                       appearance: appearance, to: "\(dir)/linked-history-\(name).png")
            let preview = ClipboardPreviewPopover(item: linked, image: store.image(for: linked))
                .frame(width: ClipboardPreviewPopover.width)
                .fixedSize(horizontal: false, vertical: true)
            try render(AnyView(preview.background(Ink.window)),
                       size: NSSize(width: ClipboardPreviewPopover.width, height: 420),
                       appearance: appearance, to: "\(dir)/linked-preview-\(name).png")
        }
    }

    /// A stand-in collage: grabbed tiles side by side with a label bar each.
    private static func collage(tiles: Int, seed: Int) -> Data {
        let tile = NSSize(width: 360, height: 220)
        let size = NSSize(width: CGFloat(tiles) * tile.width + CGFloat(tiles + 1) * 12, height: tile.height + 24)
        let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: Int(size.width), pixelsHigh: Int(size.height),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        )!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSColor(white: 0.9, alpha: 1).setFill()
        NSRect(origin: .zero, size: size).fill()
        let hues: [CGFloat] = [0.58, 0.08, 0.33, 0.75]
        for i in 0..<tiles {
            let x = 12 + CGFloat(i) * (tile.width + 12)
            let frame = NSRect(x: x, y: 12, width: tile.width, height: tile.height)
            NSColor.white.setFill(); frame.fill()
            NSColor(hue: hues[(i + seed) % hues.count], saturation: 0.55, brightness: 0.9, alpha: 1).setFill()
            NSRect(x: x, y: 12 + tile.height - 34, width: tile.width, height: 34).fill()
            NSColor(white: 0.75, alpha: 1).setFill()
            for line in 0..<5 {
                NSRect(x: x + 18, y: 30 + CGFloat(line) * 30, width: tile.width - 60 - CGFloat(line * 22), height: 12).fill()
            }
            NSColor.black.setStroke()
            let border = NSBezierPath(rect: frame.insetBy(dx: 1, dy: 1)); border.lineWidth = 2; border.stroke()
        }
        NSGraphicsContext.restoreGraphicsState()
        return rep.representation(using: .png, properties: [:])!
    }

    private func render(_ root: AnyView, size: NSSize, appearance: NSAppearance.Name, to path: String) throws {
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless],
                              backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: appearance)
        window.backgroundColor = Ink.windowNSColor
        window.alphaValue = 0
        window.ignoresMouseEvents = true
        window.setFrameOrigin(NSPoint(x: -30_000, y: -30_000))
        window.orderBack(nil)
        window.setFrameOrigin(NSPoint(x: -30_000, y: -30_000))
        let host = NSHostingView(rootView: root)
        host.frame = NSRect(origin: .zero, size: size)
        window.contentView = host
        RunLoop.main.run(until: Date().addingTimeInterval(1.2))
        if let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) {
            host.cacheDisplay(in: host.bounds, to: rep)
            try rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
        }
        window.orderOut(nil)
        window.close()
    }
}
