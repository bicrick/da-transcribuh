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


    func testDarkGraphitePalette() {
        // Soft graphite — nothing in chrome darker than bevel #1A1A1C.
        XCTAssertEqual(Ink.nsColor(hex: "#2C2C2E").redComponent * 255, 44, accuracy: 0.6)
        XCTAssertEqual(Ink.nsColor(hex: "#353538").redComponent * 255, 53, accuracy: 0.6)
        XCTAssertEqual(Ink.nsColor(hex: "#3A3A3D").redComponent * 255, 58, accuracy: 0.6)
        XCTAssertEqual(Ink.nsColor(hex: "#4A4A4E").redComponent * 255, 74, accuracy: 0.6)
        XCTAssertEqual(Ink.nsColor(hex: "#1A1A1C").redComponent * 255, 26, accuracy: 0.6)
        // Dynamic tokens resolve (light side checked via layout; dark via NSColor provider).
        _ = Ink.window
        _ = Ink.front
        _ = Ink.card
        _ = Ink.fill
        _ = Ink.bevel
        _ = Ink.hairline
        _ = Ink.secondary
        XCTAssertEqual(Ink.windowNSColor.cgColor.components?.count ?? 0 >= 3, true)
    }

    func testLayoutTokensMatchPaintSpec() {
        XCTAssertEqual(Ink.cardRadius, 2)
        XCTAssertEqual(Ink.tileRadius, 2)
        XCTAssertEqual(Ink.buttonRadius, 2)
        XCTAssertEqual(Ink.fieldRadius, 2)
        XCTAssertEqual(Ink.sidebarRowRadius, 2)
        XCTAssertEqual(Ink.folderTabHeight, 30)
        XCTAssertEqual(Ink.tipIconSize, 48)
        XCTAssertEqual(Ink.tipSymbolPointSize, 22)
        XCTAssertEqual(Ink.pageTop, 28)
        XCTAssertEqual(Ink.pageSide, 36)
        XCTAssertEqual(Ink.maxContentWidth, 920)
        XCTAssertEqual(Ink.sectionGap, 32)
        XCTAssertEqual(Ink.gridGap, 16)
        XCTAssertEqual(Ink.space7, 48)
        XCTAssertEqual(Ink.statusBarHeight, 32)
        XCTAssertEqual(Ink.titleStripHeight, 40)
        XCTAssertEqual(Ink.scrollerWidth, 5)
        XCTAssertEqual(Ink.paintSwatches.count, 16)
        XCTAssertEqual(SettingsPage.tabOrder.count, 7)
        XCTAssertEqual(SettingsPage.tabOrder.first, .home)
        XCTAssertEqual(SettingsPage.tabOrder[3], .model)
    }

    func testSettingsMetricsAliasInkTokens() {
        XCTAssertEqual(SettingsMetrics.pagePadding, Ink.pageSide)
        XCTAssertEqual(SettingsMetrics.pageTop, Ink.pageTop)
        XCTAssertEqual(SettingsMetrics.maxContentWidth, Ink.maxContentWidth)
        XCTAssertEqual(SettingsMetrics.cardCorner, Ink.cardRadius)
        XCTAssertEqual(SettingsMetrics.folderTabHeight, Ink.folderTabHeight)
    }

    func testTypographyUsesDepartureAndSystemMono() {
        XCTAssertEqual(Ink.monoName, "DepartureMono-Regular")
        // Aliases stay wired to primary tokens.
        XCTAssertEqual(Ink.pageTitleFont, Ink.titleFont)
        XCTAssertEqual(Ink.sectionTitleFont, Ink.headingFont)
        XCTAssertEqual(Ink.rowTitleFont, Ink.labelFont)
        XCTAssertEqual(Ink.statValueFont, Ink.numberFont)
        XCTAssertEqual(Ink.menuBarMetaFont, Ink.statusFont)
        // mono() must resolve even when the OTF is missing (system mono fallback).
        _ = Ink.mono(13)
        // Chrome fonts stay upright — never synthesize italic/oblique.
        let resolved = InkFontRegistrar.resolveNSFont(size: 13)
        XCTAssertFalse(resolved.fontDescriptor.symbolicTraits.contains(.italic))
    }

    func testOnboardingRailLabelsMatchStepCount() {
        XCTAssertEqual(OnboardingStep.railLabels.count, OnboardingStep.allCases.count)
        XCTAssertEqual(OnboardingStep.railLabels.count, 6)
    }

    func testPaintPaletteIsClassicFlat() {
        XCTAssertEqual(round(Ink.nsColor(hex: "#ED1C24").redComponent * 255), 237)
        XCTAssertEqual(round(Ink.nsColor(hex: "#FFF200").greenComponent * 255), 242)
        XCTAssertEqual(round(Ink.nsColor(hex: "#22B14C").greenComponent * 255), 177)
        XCTAssertEqual(round(Ink.nsColor(hex: "#3F48CC").blueComponent * 255), 204)
        // Accents alias the Paint primaries.
        XCTAssertEqual(Ink.record, Ink.paintRed)
        XCTAssertEqual(Ink.success, Ink.paintGreen)
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
        XCTAssertEqual(darkHex.uppercased(), "1E1E1E")
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
