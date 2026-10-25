import AppKit
import SwiftUI
import XCTest
@testable import PromptAnnotator

/// Offscreen renders for the screenshot-mode review: the General page pickers, the
/// crosshair with its readout, and the onboarding practice copy. Skipped unless
/// `DTShotRenderDir` is set. Windows sit far off screen at alpha 0 and never take focus.
@MainActor
final class ScreenshotModeRenderTests: XCTestCase {
    private var dir: String {
        get throws {
            guard let dir = ProcessInfo.processInfo.environment["DTShotRenderDir"], !dir.isEmpty else {
                throw XCTSkip("Set DTShotRenderDir to render screenshot mode.")
            }
            try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
            return dir
        }
    }

    private let looks: [(String, NSAppearance.Name)] = [("light", .aqua), ("dark", .darkAqua)]

    func testRenderGeneralPagePickers() throws {
        let dir = try dir
        InkFontRegistrar.registerBundledFonts()
        for (name, appearance) in looks {
            NSApp.appearance = NSAppearance(named: appearance)
            let page = ConfigurationPage(settings: AppSettings.shared)
                .frame(width: 760, height: 1080)
                .background(Ink.window)
            try render(AnyView(page), size: NSSize(width: 760, height: 1080), appearance: appearance,
                       to: "\(dir)/settings-general-\(name).png")
        }
    }

    func testRenderOnboardingPractice() throws {
        let dir = try dir
        InkFontRegistrar.registerBundledFonts()
        for (name, appearance) in looks {
            NSApp.appearance = NSAppearance(named: appearance)
            let flow = OnboardingFlow(settings: AppSettings.shared, startAt: .practice) {}
            try render(AnyView(flow), size: NSSize(width: OnboardingMetrics.width, height: OnboardingMetrics.height),
                       appearance: appearance, to: "\(dir)/onboarding-practice-\(name).png")
            let permissions = OnboardingFlow(settings: AppSettings.shared, startAt: .permissions) {}
            try render(AnyView(permissions), size: NSSize(width: OnboardingMetrics.width, height: OnboardingMetrics.height),
                       appearance: appearance, to: "\(dir)/onboarding-permissions-\(name).png")
        }
    }

    /// The real overlay canvas over a sample page, so the badge is the shipped layer.
    func testRenderCursorAndBadge() throws {
        let dir = try dir
        InkFontRegistrar.registerBundledFonts()
        let size = NSSize(width: 520, height: 300)
        for (name, appearance) in looks {
            for (label, drag) in [("idle", false), ("drag", true)] {
                let container = NSView(frame: NSRect(origin: .zero, size: size))
                container.wantsLayer = true
                container.appearance = NSAppearance(named: appearance)
                let backdrop = NSImageView(frame: container.bounds)
                backdrop.image = Self.samplePage(size: size, dark: name == "dark")
                container.addSubview(backdrop)
                let canvas = AnnotationCanvasView(frame: container.bounds)
                container.addSubview(canvas)
                let pointer = CGPoint(x: 330, y: 170)
                if drag {
                    let origin = CGPoint(x: 120, y: 70)
                    let rect = CaptureGesture.rect(from: origin, to: pointer)
                    canvas.setSelection(rect)
                    canvas.setBadge(.size(of: rect, at: pointer))
                } else {
                    canvas.setBadge(.position(pointer))
                }
                let cursor = NSImageView(frame: NSRect(
                    x: pointer.x - ScreenshotCursor.size.width / 2,
                    y: size.height - pointer.y - ScreenshotCursor.size.height / 2,
                    width: ScreenshotCursor.size.width,
                    height: ScreenshotCursor.size.height
                ))
                cursor.image = ScreenshotCursor.image()
                container.addSubview(cursor)
                let window = offscreenWindow(size: size, appearance: appearance)
                window.contentView = container
                spin(0.5)
                try snapshot(container, to: "\(dir)/cursor-badge-\(label)-\(name).png")
                window.orderOut(nil)
                window.close()
            }
        }
        // The cursor alone at 4x, to check the halo and the open center.
        let big = NSImage(size: NSSize(width: 108, height: 108), flipped: false) { rect in
            NSColor(white: 0.5, alpha: 1).setFill()
            rect.fill()
            NSGraphicsContext.current?.imageInterpolation = .none
            ScreenshotCursor.image().draw(in: rect)
            return true
        }
        if let tiff = big.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) {
            try rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: "\(dir)/cursor-4x.png"))
        }
    }

    // MARK: - Helpers

    private static func samplePage(size: NSSize, dark: Bool) -> NSImage {
        NSImage(size: size, flipped: true) { rect in
            (dark ? NSColor(white: 0.12, alpha: 1) : NSColor(white: 0.97, alpha: 1)).setFill()
            rect.fill()
            let ink = dark ? NSColor(white: 0.85, alpha: 1) : NSColor(white: 0.15, alpha: 1)
            let title: [NSAttributedString.Key: Any] = [.font: NSFont.boldSystemFont(ofSize: 22), .foregroundColor: ink]
            let body: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 13), .foregroundColor: ink.withAlphaComponent(0.75)]
            ("Release notes" as NSString).draw(at: NSPoint(x: 28, y: 26), withAttributes: title)
            for line in 0..<9 {
                let text = "Line \(line + 1). Hold Shift and drag to grab this part of the page." as NSString
                text.draw(at: NSPoint(x: 28, y: 70 + CGFloat(line) * 24), withAttributes: body)
            }
            NSColor.systemBlue.withAlphaComponent(0.85).setFill()
            NSBezierPath(roundedRect: NSRect(x: 380, y: 30, width: 110, height: 30), xRadius: 6, yRadius: 6).fill()
            return true
        }
    }

    private func offscreenWindow(size: NSSize, appearance: NSAppearance.Name) -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: appearance)
        window.backgroundColor = Ink.windowNSColor
        window.alphaValue = 0
        window.ignoresMouseEvents = true
        window.setFrameOrigin(NSPoint(x: -30_000, y: -30_000))
        window.orderBack(nil)
        window.setFrameOrigin(NSPoint(x: -30_000, y: -30_000))
        return window
    }

    private func render(_ root: AnyView, size: NSSize, appearance: NSAppearance.Name, to path: String, crop: CGFloat? = nil) throws {
        let window = offscreenWindow(size: size, appearance: appearance)
        let host = NSHostingView(rootView: root)
        host.frame = NSRect(origin: .zero, size: size)
        window.contentView = host
        spin(1.2)
        var bounds = host.bounds
        if let crop, crop < bounds.height {
            bounds = NSRect(x: 0, y: host.isFlipped ? 0 : bounds.height - crop, width: bounds.width, height: crop)
        }
        if let rep = host.bitmapImageRepForCachingDisplay(in: bounds) {
            host.cacheDisplay(in: bounds, to: rep)
            try rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
        }
        window.orderOut(nil)
        window.close()
    }

    /// Layer render, so the overlay's CALayers (selection, badge) are included.
    private func snapshot(_ view: NSView, to path: String) throws {
        view.layoutSubtreeIfNeeded()
        view.displayIfNeeded()
        let scale: CGFloat = 2
        let width = Int(view.bounds.width * scale)
        let height = Int(view.bounds.height * scale)
        guard let layer = view.layer,
              let context = CGContext(
                data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
              ) else { return }
        context.scaleBy(x: scale, y: scale)
        layer.render(in: context)
        guard let image = context.makeImage() else { return }
        let rep = NSBitmapImageRep(cgImage: image)
        try rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
    }

    private func spin(_ seconds: TimeInterval) {
        RunLoop.main.run(until: Date().addingTimeInterval(seconds))
    }
}
