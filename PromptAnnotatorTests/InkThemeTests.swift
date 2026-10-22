import AppKit
import XCTest
@testable import PromptAnnotator

final class InkThemeTests: XCTestCase {
    func testPaletteHexesParse() {
        let lightAccent = Ink.nsColor(hex: "#E5432F")
        let darkAccent = Ink.nsColor(hex: "#FF6A55")
        XCTAssertEqual(round(lightAccent.redComponent * 255), 229)
        XCTAssertEqual(round(lightAccent.greenComponent * 255), 67)
        XCTAssertEqual(round(lightAccent.blueComponent * 255), 47)
        XCTAssertEqual(round(darkAccent.redComponent * 255), 255)
        XCTAssertEqual(round(darkAccent.greenComponent * 255), 106)
        XCTAssertEqual(round(darkAccent.blueComponent * 255), 85)
    }

    func testLayoutTokensMatchSpec() {
        XCTAssertEqual(Ink.cardRadius, 12)
        XCTAssertEqual(Ink.tileRadius, 14)
        XCTAssertEqual(Ink.buttonRadius, 7)
        XCTAssertEqual(Ink.buttonLargeRadius, 9)
        XCTAssertEqual(Ink.fieldRadius, 7)
        XCTAssertEqual(Ink.sidebarRowRadius, 8)
        XCTAssertEqual(Ink.keycapRadius, 8)
        XCTAssertEqual(Ink.sidebarWidth, 220)
        // Post–title-bar breathing room only (system safe area already clears the chrome).
        XCTAssertEqual(Ink.pageTop, 22)
        XCTAssertEqual(Ink.pageSide, 36)
        XCTAssertEqual(Ink.maxContentWidth, 680)
        XCTAssertEqual(Ink.sectionGap, 28)
        XCTAssertEqual(Ink.gridGap, 12)
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
        // Constructing the view must not trap on out-of-range fractions.
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
        XCTAssertEqual(lightHex.uppercased(), "F6F2EC")
        XCTAssertEqual(darkHex.uppercased(), "1D1A17")
        XCTAssertNotEqual(lightHex, darkHex)
    }

    private func hexRGB(resolved color: NSColor) -> String {
        // cgColor resolves dynamic providers against the current drawing appearance.
        guard let rgb = NSColor(cgColor: color.cgColor)?.usingColorSpace(.sRGB) else {
            return ""
        }
        let r = Int((rgb.redComponent * 255).rounded())
        let g = Int((rgb.greenComponent * 255).rounded())
        let b = Int((rgb.blueComponent * 255).rounded())
        return String(format: "%02X%02X%02X", r, g, b)
    }
}
