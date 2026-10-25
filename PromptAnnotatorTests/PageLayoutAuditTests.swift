import AppKit
import SwiftUI
import XCTest
@testable import PromptAnnotator

/// Offscreen render of every Settings page plus onboarding, for the page
/// consistency audit. Skipped unless `DTPageAuditDir` is set:
///
///     TEST_RUNNER_DTPageAuditDir=/tmp/audit xcodebuild test \
///       -only-testing:PromptAnnotatorTests/PageLayoutAuditTests
///
/// Add `TEST_RUNNER_DTPageAuditForceHover=1` to draw every hover state on.
///
/// The window sits far off screen at alpha 0 and never becomes key, so
/// nothing appears and focus does not move. `cacheDisplay` draws it.
@MainActor
final class PageLayoutAuditTests: XCTestCase {
    private var log = ""

    func testRenderEveryPageOffscreen() throws {
        guard let dir = ProcessInfo.processInfo.environment["DTPageAuditDir"], !dir.isEmpty else {
            throw XCTSkip("Set DTPageAuditDir to render the page audit.")
        }
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        InkFontRegistrar.registerBundledFonts()
        // `DTPageAuditForceHover=1` draws every hover target hovered, to review coverage.
        RetroHover.forceAll = ProcessInfo.processInfo.environment["DTPageAuditForceHover"] == "1"
        defer { RetroHover.forceAll = false }

        for (name, appearance) in [("light", NSAppearance.Name.aqua), ("dark", NSAppearance.Name.darkAqua)] {
            NSApp.appearance = NSAppearance(named: appearance)
            let root = SettingsRoot()
                .environmentObject(AppSettings.shared)
                .environmentObject(SessionController.shared)
            let window = makeWindow(root: AnyView(root), size: NSSize(width: 1040, height: 700), appearance: appearance)
            spin(1.5)
            for page in SettingsPage.tabOrder {
                NotificationCenter.default.post(name: .promptAnnotatorSettingsSelectPage, object: page.rawValue)
                spin(1.2)
                capture(window: window, label: "\(name)-\(page.rawValue)", dir: dir)
            }
            window.orderOut(nil)
            window.close()

            let onboarding = OnboardingFlow(settings: AppSettings.shared) {}
            let flow = makeWindow(
                root: AnyView(onboarding),
                size: NSSize(width: OnboardingMetrics.width, height: OnboardingMetrics.height),
                appearance: appearance
            )
            spin(1.5)
            capture(window: flow, label: "\(name)-onboarding", dir: dir)
            flow.orderOut(nil)
            flow.close()
        }
        try log.write(toFile: "\(dir)/audit.log", atomically: true, encoding: .utf8)
    }

    // MARK: - Helpers

    private func makeWindow(root: AnyView, size: NSSize, appearance: NSAppearance.Name) -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.titlebarSeparatorStyle = .none
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: appearance)
        window.backgroundColor = Ink.windowNSColor
        window.alphaValue = 0
        window.ignoresMouseEvents = true
        let host = NSHostingView(rootView: root)
        host.autoresizingMask = [.width, .height]
        window.contentView = host
        window.setContentSize(size)
        window.setFrameOrigin(NSPoint(x: -30_000, y: -30_000))
        // Ordered in (behind everything, invisible) so SwiftUI treats it as live.
        window.orderBack(nil)
        window.setFrameOrigin(NSPoint(x: -30_000, y: -30_000))
        return window
    }

    private func capture(window: NSWindow, label: String, dir: String) {
        guard let content = window.contentView else { return }
        var line = "\(label) window=\(Int(content.bounds.width))x\(Int(content.bounds.height))"
        if let scroll = pageScroll(in: content), let doc = scroll.documentView {
            let clip = scroll.contentView
            let hosting = doc.subviews.first
            line += " clipY0=\(fmt(clip.bounds.origin.y)) clipW=\(fmt(clip.bounds.width))"
            line += " viewport=\(fmt(clip.bounds.height)) doc=\(fmt(doc.frame.height))"
            if let hosting {
                line += " hostingH=\(fmt(hosting.frame.height)) intrinsicH=\(fmt(hosting.intrinsicContentSize.height))"
            }
            clip.scroll(to: .zero)
            scroll.reflectScrolledClipView(clip)
            spin(0.4)
            write(doc, to: "\(dir)/\(label)-doc.png")
        } else {
            line += " noscroll"
        }
        write(content, to: "\(dir)/\(label).png")
        log += line + "\n"
    }

    private func pageScroll(in root: NSView) -> NSScrollView? {
        var best: NSScrollView?
        var stack = [root]
        while let view = stack.popLast() {
            if let s = view as? NSScrollView, let d = s.documentView, d.frame.height > 0,
               s.frame.height > (best?.frame.height ?? 0) {
                best = s
            }
            stack.append(contentsOf: view.subviews)
        }
        return best
    }

    private func write(_ view: NSView, to path: String) {
        let bounds = view.bounds
        guard bounds.width > 0, bounds.height > 0,
              let rep = view.bitmapImageRepForCachingDisplay(in: bounds) else { return }
        view.cacheDisplay(in: bounds, to: rep)
        guard let data = rep.representation(using: .png, properties: [:]) else { return }
        try? data.write(to: URL(fileURLWithPath: path))
    }

    private func spin(_ seconds: TimeInterval) {
        RunLoop.main.run(until: Date().addingTimeInterval(seconds))
    }

    private func fmt(_ v: CGFloat) -> String { String(format: "%.1f", v) }
}
