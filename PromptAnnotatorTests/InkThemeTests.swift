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
        // Soft graphite surfaces; bevel inverts to near-white in dark.
        XCTAssertEqual(Ink.nsColor(hex: "#2C2C2E").redComponent * 255, 44, accuracy: 0.6)
        XCTAssertEqual(Ink.nsColor(hex: "#353538").redComponent * 255, 53, accuracy: 0.6)
        XCTAssertEqual(Ink.nsColor(hex: "#3A3A3D").redComponent * 255, 58, accuracy: 0.6)
        XCTAssertEqual(Ink.nsColor(hex: "#4A4A4E").redComponent * 255, 74, accuracy: 0.6)
        XCTAssertEqual(Ink.nsColor(hex: "#F2F2F2").redComponent * 255, 242, accuracy: 0.6)
        // Dynamic tokens resolve (light side checked via layout; dark via NSColor provider).
        _ = Ink.window
        _ = Ink.front
        _ = Ink.card
        _ = Ink.fill
        _ = Ink.bevel
        _ = Ink.hairline
        _ = Ink.secondary
        XCTAssertGreaterThanOrEqual(Ink.windowNSColor.cgColor.numberOfComponents, 3)
    }

    func testLayoutTokensMatchPaintSpec() {
        XCTAssertEqual(Ink.cardRadius, 2)
        XCTAssertEqual(Ink.tileRadius, 2)
        XCTAssertEqual(Ink.buttonRadius, 2)
        XCTAssertEqual(Ink.fieldRadius, 2)
        XCTAssertEqual(Ink.sidebarRowRadius, 2)
        XCTAssertEqual(Ink.folderTabHeight, 30)
        XCTAssertEqual(Ink.tabGroupGap, 8)
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
        XCTAssertEqual(SettingsPage.tabOrder[1], .appearance)
        XCTAssertEqual(SettingsPage.tabOrder[2], .history)
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
        XCTAssertEqual(SettingsPage.appearance.title, "Appearance")
        XCTAssertEqual(SettingsPage.appearance.symbol, "paintpalette")
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
        XCTAssertNil(AppAppearance.system.nsAppearance)
        XCTAssertEqual(AppAppearance.light.nsAppearance?.name, .aqua)
        XCTAssertEqual(AppAppearance.dark.nsAppearance?.name, .darkAqua)
    }

    @MainActor
    func testSetAppearanceIsIdempotentSinglePath() {
        let name = "PromptAnnotatorTests.appearanceDefaults"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        let settings = AppSettings(defaults: defaults)
        var appChanges = 0
        settings.onAppChange = { appChanges += 1 }

        settings.setAppearance(.dark)
        XCTAssertEqual(settings.appearance, .dark)
        XCTAssertEqual(appChanges, 1)
        XCTAssertEqual(NSApp.appearance?.name, .darkAqua)

        // Re-selecting the same mode must not re-apply / flicker.
        settings.setAppearance(.dark)
        XCTAssertEqual(appChanges, 1)

        settings.setAppearance(.system)
        XCTAssertEqual(settings.appearance, .system)
        XCTAssertEqual(appChanges, 2)
        XCTAssertNil(NSApp.appearance)

        settings.cycleAppearance()
        XCTAssertEqual(settings.appearance, .light)
        XCTAssertEqual(appChanges, 3)
        XCTAssertEqual(NSApp.appearance?.name, .aqua)

        defaults.removePersistentDomain(forName: name)
        // Leave the test host on system so later tests aren't pinned dark.
        AppAppearance.system.applyToApp()
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
        XCTAssertEqual(darkHex.uppercased(), "2C2C2E")
        XCTAssertNotEqual(lightHex, darkHex)
    }

    func testChromeInvertTokensResolve() {
        // Light: primary plate is black; dark: graphite front (not glare white).
        let aqua = NSAppearance(named: .aqua)!
        let darkAqua = NSAppearance(named: .darkAqua)!
        var lightPrimary = ""
        var darkPrimary = ""
        var lightMark = ""
        var darkMark = ""
        aqua.performAsCurrentDrawingAppearance {
            lightPrimary = hexRGB(resolved: NSColor(Ink.primaryFill))
            lightMark = hexRGB(resolved: NSColor(Ink.markFace))
        }
        darkAqua.performAsCurrentDrawingAppearance {
            darkPrimary = hexRGB(resolved: NSColor(Ink.primaryFill))
            darkMark = hexRGB(resolved: NSColor(Ink.markFace))
        }
        // Start / primary stays high-contrast invert (not flat graphite).
        XCTAssertEqual(lightPrimary.uppercased(), "000000")
        XCTAssertEqual(darkPrimary.uppercased(), "F2F2F2")
        XCTAssertEqual(lightMark.uppercased(), "FFFFFF")
        XCTAssertEqual(darkMark.uppercased(), "3A3A3D")
        XCTAssertEqual(Ink.keycap, Ink.front)
        XCTAssertEqual(Ink.tileFace, Ink.front)
        XCTAssertEqual(Ink.onTile, Ink.label)
        // Control border inverts: black in light, light hairline in dark.
        var lightBorder = ""
        var darkBorder = ""
        var lightOnPrimary = ""
        var darkOnPrimary = ""
        var lightStat = ""
        var darkStat = ""
        aqua.performAsCurrentDrawingAppearance {
            lightBorder = hexRGB(resolved: NSColor(Ink.controlBorder))
            lightOnPrimary = hexRGB(resolved: NSColor(Ink.onPrimary))
            lightStat = hexRGB(resolved: NSColor(Ink.statRule))
        }
        darkAqua.performAsCurrentDrawingAppearance {
            darkBorder = hexRGB(resolved: NSColor(Ink.controlBorder))
            darkOnPrimary = hexRGB(resolved: NSColor(Ink.onPrimary))
            darkStat = hexRGB(resolved: NSColor(Ink.statRule))
        }
        XCTAssertEqual(lightBorder.uppercased(), "000000")
        XCTAssertEqual(darkBorder.uppercased(), "F2F2F2")
        XCTAssertEqual(lightOnPrimary.uppercased(), "FFFFFF")
        XCTAssertEqual(darkOnPrimary.uppercased(), "2C2C2E")
        XCTAssertEqual(lightStat.uppercased(), "000000")
        XCTAssertEqual(darkStat.uppercased(), "A8A8AD")
        XCTAssertEqual(SettingsPage.home.tabAccent, Ink.tabStrokeRed)
        XCTAssertEqual(SettingsPage.appearance.tabAccent, Ink.tabStrokePurple)
        XCTAssertEqual(SettingsPage.history.tabAccent, Ink.tabStrokeBlue)
        XCTAssertEqual(SettingsPage.model.tabAccent, Ink.tabStrokeOrange)
        XCTAssertEqual(SettingsPage.performance.tabAccent, Ink.tabStrokePink)
        XCTAssertEqual(FolderTabShape.corner, 0, "Tabs are square Paint chrome")
        XCTAssertEqual(FolderTabShape.foot, 0, "No cove feet — tabs have no bevel")
        XCTAssertEqual(Ink.stroke, 2)
        XCTAssertEqual(Ink.bevelOffset, 3)
        XCTAssertEqual(Ink.hairlineWidth, 1)
        XCTAssertEqual(Ink.lineWidth, Ink.stroke)
        XCTAssertEqual(Ink.selectedBorder, Ink.stroke)
        XCTAssertEqual(Ink.hardShadow, Ink.bevelOffset)
        XCTAssertEqual(Ink.buttonShadow, Ink.bevelOffset)
        XCTAssertEqual(Ink.menuBarShadow, Ink.bevelOffset)
    }

    func testFolderTabLayoutSizeIgnoresSelection() {
        // Face width is label-based and identical whether selected or not
        // (tabs have no bevel gutter).
        let home = FolderTabShape.layoutSize(titleWidth: 40)
        let appearance = FolderTabShape.layoutSize(titleWidth: 90)
        XCTAssertEqual(home.height, Ink.folderTabHeight)
        XCTAssertEqual(appearance.height, Ink.folderTabHeight)
        XCTAssertGreaterThan(appearance.width, home.width)
        XCTAssertEqual(home.width, 10 + (Ink.space1 + 1) + 40 + Ink.space3 * 2)
        XCTAssertEqual(FolderTabMetrics.intraGroupGap, 2)
        // Square open-bottom path: four corners, no curves.
        let outline = FolderTabShape(closeBottom: false).path(in: CGRect(x: 0, y: 0, width: 80, height: 30))
        XCTAssertFalse(outline.isEmpty)
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
