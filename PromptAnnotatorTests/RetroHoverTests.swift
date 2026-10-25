import AppKit
import SwiftUI
import XCTest
@testable import PromptAnnotator

/// Shared hover: one modifier, fast eased fade, 1pt lift, no layout change.
@MainActor
final class RetroHoverTests: XCTestCase {
    private func source(_ path: String) throws -> String {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("PromptAnnotator").appendingPathComponent(path)
        guard let text = try? String(contentsOf: url, encoding: .utf8) else {
            throw XCTSkip("sources not readable from the test host")
        }
        return text
    }

    func testTimingIsFastAndLiftIsOnePoint() {
        XCTAssertGreaterThanOrEqual(Ink.hoverDuration, 0.12)
        XCTAssertLessThanOrEqual(Ink.hoverDuration, 0.15)
        XCTAssertEqual(Ink.hoverLift, 1)
        XCTAssertLessThan(Ink.hoverLift, Ink.bevelOffset, "the lift must stay inside the bevel gutter")
    }

    func testTintsResolveInBothAppearances() {
        for name in [NSAppearance.Name.aqua, .darkAqua] {
            let appearance = NSAppearance(named: name)!
            appearance.performAsCurrentDrawingAppearance {
                for tint in [Ink.hoverTint, Ink.hoverTintOnPrimary] {
                    let ns = NSColor(tint).usingColorSpace(.sRGB)
                    XCTAssertNotNil(ns)
                    // Subtle wash: visible, never more than a fifth opaque.
                    XCTAssertGreaterThan(ns?.alphaComponent ?? 0, 0.02)
                    XCTAssertLessThanOrEqual(ns?.alphaComponent ?? 1, 0.2)
                }
            }
        }
    }

    /// Hovering must not resize anything: same fitting size at rest and hovered.
    func testHoverDoesNotChangeLayout() {
        defer { RetroHover.forceAll = false }
        func size(forced: Bool) -> CGSize {
            RetroHover.forceAll = forced
            let host = NSHostingView(rootView: HoverGallery())
            return host.fittingSize
        }
        XCTAssertEqual(size(forced: false), size(forced: true))
    }

    func testSharedPiecesUseTheModifier() throws {
        let components = try source("Settings/Ink/InkComponents.swift")
        let chrome = components.components(separatedBy: "func inkSecondaryChrome").last ?? ""
        XCTAssertTrue(chrome.contains(".retroHover("), "secondary buttons")
        let tile = components.components(separatedBy: "struct InkTile").last ?? ""
        XCTAssertTrue(tile.contains(".retroHover("), "selectable tiles")
        XCTAssertTrue(try source("Settings/SettingsFolderTabs.swift").contains(".retroHover("), "folder tabs")
        XCTAssertFalse(try source("Settings/Ink/InkHover.swift").contains("focusable"), "no focus rings")
    }

    /// Offscreen before/after sheet of the hover states. Skipped unless
    /// `DTHoverRenderDir` is set. Nothing appears on screen.
    func testRenderHoverGalleryOffscreen() throws {
        guard let dir = ProcessInfo.processInfo.environment["DTHoverRenderDir"], !dir.isEmpty else {
            throw XCTSkip("Set DTHoverRenderDir to render the hover gallery.")
        }
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        InkFontRegistrar.registerBundledFonts()
        defer { RetroHover.forceAll = false }
        for (name, appearance) in [("light", NSAppearance.Name.aqua), ("dark", NSAppearance.Name.darkAqua)] {
            NSApp.appearance = NSAppearance(named: appearance)
            for forced in [false, true] {
                RetroHover.forceAll = forced
                let window = NSWindow(
                    contentRect: NSRect(x: 0, y: 0, width: 760, height: 470),
                    styleMask: [.borderless],
                    backing: .buffered,
                    defer: false
                )
                window.isReleasedWhenClosed = false
                window.appearance = NSAppearance(named: appearance)
                window.backgroundColor = Ink.windowNSColor
                window.alphaValue = 0
                window.ignoresMouseEvents = true
                let host = NSHostingView(rootView: HoverGallery().frame(width: 760, height: 470))
                window.contentView = host
                window.setFrameOrigin(NSPoint(x: -30_000, y: -30_000))
                window.orderBack(nil)
                window.setFrameOrigin(NSPoint(x: -30_000, y: -30_000))
                RunLoop.main.run(until: Date().addingTimeInterval(0.8))
                if let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) {
                    host.cacheDisplay(in: host.bounds, to: rep)
                    let path = "\(dir)/hover-gallery-\(name)-\(forced ? "hover" : "rest").png"
                    try rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
                }
                window.orderOut(nil)
                window.close()
            }
        }
    }
}

/// One of each hover target, for the layout check and the render sheet.
private struct HoverGallery: View {
    var body: some View {
        VStack(alignment: .leading, spacing: Ink.space4) {
            SettingsFolderTabs(selection: .constant(.home))
            VStack(alignment: .leading, spacing: Ink.space4) {
                HStack(spacing: Ink.space3) {
                    Button {} label: {
                        InkTile(selected: true) { Text("Selected tile").font(Ink.tileTitleFont) }
                    }
                    .buttonStyle(.plain)
                    Button {} label: {
                        InkTile(selected: false) { Text("Other tile").font(Ink.tileTitleFont) }
                    }
                    .buttonStyle(.plain)
                }
                .frame(height: 70)
                HStack(spacing: Ink.space4) {
                    Button("Start") {}
                        .buttonStyle(InkPrimaryButtonStyle(large: true, lift: .upLeft))
                        .background(Rectangle().fill(Ink.paintRed).offset(x: Ink.bevelOffset, y: Ink.bevelOffset))
                    Button("Save") {}.buttonStyle(InkPrimaryButtonStyle(large: false))
                    Button("Copy") {}.buttonStyle(InkSecondaryButtonStyle())
                    InkMenuPicker(title: "Mode", selection: .constant(0), options: [(0, "Toggle"), (1, "Hold")])
                    InkShortcutRecorder(keys: ["⌥", "Space"], listening: false) {}
                    InkStepper(title: "Count", value: .constant(5), range: 0...10)
                }
                HStack(spacing: Ink.space4) {
                    InkAppearanceSegment(selection: .constant(.system)).frame(width: 260)
                    InkRadioGroup(title: "Paste", selection: .constant(0), options: [(0, "Auto"), (1, "Never")], axis: .horizontal)
                }
                InkToggleRow(title: "Enable clipboard history", detail: "Toggle rows wash end to end.", isOn: .constant(true))
                    .background(Ink.card)
            }
            .padding(.horizontal, Ink.pageSide)
            Spacer(minLength: 0)
        }
        .background(Ink.front)
    }
}
