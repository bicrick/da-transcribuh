import XCTest
@testable import PromptAnnotator

final class FontMetricsTests: XCTestCase {
    func testWidthNeverReturnsZeroForClockAndLabelStrings() {
        let clock = FontMetrics.width(of: "12:34", size: 13, weight: .medium, mono: true)
        XCTAssertGreaterThan(clock, 20)

        let label = FontMetrics.width(of: "Recording", size: 13, weight: .semibold, mono: false)
        XCTAssertGreaterThan(label, 40)

        let chip = FontMetrics.width(of: "9", size: 13, weight: .semibold, mono: true)
        XCTAssertGreaterThan(chip, 4)
    }

    func testFontsAreReusableInAttributesDictionaries() {
        for mono in [false, true] {
            for weight in [NSFont.Weight.regular, .medium, .semibold, .bold] {
                let font = FontMetrics.font(size: 13, weight: weight, mono: mono)
                XCTAssertGreaterThan(font.pointSize, 0)
                XCTAssertFalse(font.fontName.isEmpty)
                let width = ("Aa0" as NSString).size(withAttributes: [.font: font]).width
                XCTAssertGreaterThan(width, 0)
            }
        }
    }

    func testIslandLayoutSurvivesClockTick() {
        let early = IslandMetrics.layout(
            style: .classic,
            slots: IslandSlots.recording(style: .classic, captures: 1),
            captures: 1,
            elapsed: 0
        )
        let later = IslandMetrics.layout(
            style: .classic,
            slots: IslandSlots.recording(style: .classic, captures: 1),
            captures: 1,
            elapsed: 3_661
        )
        XCTAssertGreaterThan(early.panel.width, 100)
        XCTAssertGreaterThanOrEqual(later.clock, early.clock)
    }
}
