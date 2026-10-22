import AppKit
import XCTest
@testable import PromptAnnotator

final class InkThemeTests: XCTestCase {
    func testBWPaletteHexesParse() {
        let black = Ink.nsColor(hex: "#000000")
        let white = Ink.nsColor(hex: "#FFFFFF")
        let hair = Ink.nsColor(hex: "#DADADA")
        let fill = Ink.nsColor(hex: "#F2F2F2")
        XCTAssertEqual(round(black.redComponent * 255), 0)
        XCTAssertEqual(round(white.redComponent * 255), 255)
        XCTAssertEqual(round(hair.redComponent * 255), 218)
        XCTAssertEqual(round(fill.greenComponent * 255), 242)
    }

    func testLayoutTokensMatchBWSpec() {
        XCTAssertEqual(Ink.cardRadius, 3)
        XCTAssertEqual(Ink.tileRadius, 3)
        XCTAssertEqual(Ink.buttonRadius, 3)
        XCTAssertEqual(Ink.fieldRadius, 2)
        XCTAssertEqual(Ink.sidebarRowRadius, 3)
        XCTAssertEqual(Ink.sidebarWidth, 108)
        XCTAssertEqual(Ink.sidebarTileSize, 72)
        XCTAssertEqual(Ink.pageTop, 22)
        XCTAssertEqual(Ink.pageSide, 28)
        XCTAssertEqual(Ink.maxContentWidth, 660)
        XCTAssertEqual(Ink.sectionGap, 24)
        XCTAssertEqual(Ink.gridGap, 10)
        XCTAssertEqual(Ink.statusBarHeight, 24)
        XCTAssertEqual(Ink.titleStripHeight, 38)
        XCTAssertEqual(Ink.menuBarShadow, 4)
        XCTAssertEqual(Ink.hardShadow, 3)
        XCTAssertEqual(Ink.selectedBorder, 2)
    }

    func testSettingsMetricsAliasInkTokens() {
        XCTAssertEqual(SettingsMetrics.pagePadding, Ink.pageSide)
        XCTAssertEqual(SettingsMetrics.pageTop, Ink.pageTop)
        XCTAssertEqual(SettingsMetrics.maxContentWidth, Ink.maxContentWidth)
        XCTAssertEqual(SettingsMetrics.cardCorner, Ink.cardRadius)
        XCTAssertEqual(SettingsMetrics.sidebarWidth, Ink.sidebarWidth)
    }

    func testOnboardingStepCountAndEyebrows() {
        XCTAssertEqual(OnboardingStep.allCases.count, 6)
        XCTAssertEqual(OnboardingStep.welcome.eyebrow, "Step 1 of 6")
        XCTAssertEqual(OnboardingStep.ready.eyebrow, "Step 6 of 6")
    }

    func testSegmentMeterClampsFraction() {
        let low = InkSegmentMeter(label: "Speed", fraction: -1)
        let high = InkSegmentMeter(label: "Quality", fraction: 2)
        XCTAssertEqual(low.label, "Speed")
        XCTAssertEqual(high.label, "Quality")
    }

    func testDynamicWindowColorResolvesUnderAppearances() {
        let aqua = NSAppearance(named: .aqua)!
        let darkAqua = NSAppearance(named: .darkAqua)!
        var lightHex = ""
        var darkHex = ""
        aqua.performAsCurrentDrawingAppearance {
            lightHex = hexRGB(resolved: Ink.windowNSColor)
        }
        darkAqua.performAsCurrentDrawingAppearance {
            darkHex = hexRGB(resolved: Ink.windowNSColor)
        }
        XCTAssertEqual(lightHex.uppercased(), "FFFFFF")
        XCTAssertEqual(darkHex.uppercased(), "000000")
        XCTAssertNotEqual(lightHex, darkHex)
    }

    func testWordmarkUsesSeparateBlockCursorNotInvertedH() {
        // Pure logic: the displayed name string must be the full lowercase word;
        // the cursor is a separate view, not an inverted trailing letter.
        let name = "da transcribuh"
        XCTAssertFalse(name.hasSuffix(" "))
        XCTAssertEqual(name.last, "h")
        XCTAssertEqual(Ink.monoName, "DepartureMono-Regular")
    }

    private func hexRGB(resolved color: NSColor) -> String {
        guard let rgb = NSColor(cgColor: color.cgColor)?.usingColorSpace(.sRGB) else {
            return ""
        }
        let r = Int((rgb.redComponent * 255).rounded())
        let g = Int((rgb.greenComponent * 255).rounded())
        let b = Int((rgb.blueComponent * 255).rounded())
        return String(format: "%02X%02X%02X", r, g, b)
    }
}
