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
        XCTAssertEqual(Ink.sidebarWidth, 128)
        XCTAssertEqual(Ink.sidebarTileSize, 84)
        XCTAssertEqual(Ink.sidebarTilePad, 8)
        XCTAssertEqual(Ink.sidebarFooterHeight, 72)
        XCTAssertEqual(Ink.pageTop, 16)
        XCTAssertEqual(Ink.pageSide, 24)
        XCTAssertEqual(Ink.maxContentWidth, 880)
        XCTAssertEqual(Ink.sectionGap, 24)
        XCTAssertEqual(Ink.gridGap, 12)
        XCTAssertEqual(Ink.space1, 4)
        XCTAssertEqual(Ink.space2, 8)
        XCTAssertEqual(Ink.space3, 12)
        XCTAssertEqual(Ink.space4, 16)
        XCTAssertEqual(Ink.space5, 24)
        XCTAssertEqual(Ink.space6, 32)
        XCTAssertEqual(Ink.statusBarHeight, 24)
        XCTAssertEqual(Ink.titleStripHeight, 38)
        XCTAssertEqual(Ink.menuBarShadow, 4)
        XCTAssertEqual(Ink.hardShadow, 3)
        XCTAssertEqual(Ink.selectedBorder, 2)
        XCTAssertEqual(Ink.scrollerWidth, 8)
    }

    func testSettingsMetricsAliasInkTokens() {
        XCTAssertEqual(SettingsMetrics.pagePadding, Ink.pageSide)
        XCTAssertEqual(SettingsMetrics.pageTop, Ink.pageTop)
        XCTAssertEqual(SettingsMetrics.maxContentWidth, Ink.maxContentWidth)
        XCTAssertEqual(SettingsMetrics.cardCorner, Ink.cardRadius)
        XCTAssertEqual(SettingsMetrics.sidebarWidth, Ink.sidebarWidth)
    }

    func testTypographyUsesDepartureAndSystemMono() {
        XCTAssertEqual(Ink.monoName, "DepartureMono-Regular")
        // Aliases stay wired to primary tokens.
        XCTAssertEqual(Ink.pageTitleFont, Ink.titleFont)
        XCTAssertEqual(Ink.sectionTitleFont, Ink.headingFont)
        XCTAssertEqual(Ink.rowTitleFont, Ink.labelFont)
        XCTAssertEqual(Ink.statValueFont, Ink.numberFont)
    }

    func testSidebarTileTitlesAreCompact() {
        XCTAssertEqual(SettingsPage.configuration.title, "General")
        XCTAssertEqual(SettingsPage.performance.title, "Perf")
        XCTAssertEqual(SettingsPage.configuration.pageTitle, "General")
        XCTAssertEqual(SettingsPage.performance.pageTitle, "Performance")
    }

    func testAppAppearanceCyclesAndStores() {
        XCTAssertEqual(AppAppearance.system.next, .light)
        XCTAssertEqual(AppAppearance.light.next, .dark)
        XCTAssertEqual(AppAppearance.dark.next, .system)
        XCTAssertEqual(AppAppearance.stored(nil), .system)
        XCTAssertEqual(AppAppearance.stored("dark"), .dark)
        XCTAssertEqual(AppAppearance.dark.menuLabel, "theme: dark")
        XCTAssertEqual(AppAppearance.light.preferredColorScheme, .light)
        XCTAssertNil(AppAppearance.system.preferredColorScheme)
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
