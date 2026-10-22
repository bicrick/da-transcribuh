import AppKit
import SwiftUI

/// "da transcribuh" chrome — strict black/white, 1px lines, hard offset shadows.
/// Kept under the `Ink` name so existing call sites stay compile-safe.
enum Ink {
    // MARK: - Dynamic colors (light / dark)

    static let window = color(light: "#FFFFFF", dark: "#000000")
    static let canvas = color(light: "#FFFFFF", dark: "#000000")
    static let label = color(light: "#000000", dark: "#FFFFFF")
    static let onAccent = color(light: "#FFFFFF", dark: "#000000")
    /// Primary fill / border rule (was red accent).
    static let accent = label
    static let accentSoft = fill
    static let sidebarSelection = label
    static let hairline = color(light: "#DADADA", dark: "#333333")
    static let borderStrong = label
    static let fill = color(light: "#F2F2F2", dark: "#141414")
    static let track = hairline
    static let meter = label
    static let secondary = color(light: "#666666", dark: "#A0A0A0")
    static let tertiary = color(light: "#A3A3A3", dark: "#5C5C5C")
    static let field = window
    static let card = window
    static let keycap = window
    static let sidebar = window
    static let success = label
    static let error = label

    // MARK: - Radii / stroke

    static let cardRadius: CGFloat = 3
    static let tileRadius: CGFloat = 3
    static let buttonRadius: CGFloat = 3
    static let buttonLargeRadius: CGFloat = 3
    static let fieldRadius: CGFloat = 2
    static let sidebarRowRadius: CGFloat = 3
    static let keycapRadius: CGFloat = 3
    static let lineWidth: CGFloat = 1
    static let selectedBorder: CGFloat = 2
    static let hardShadow: CGFloat = 3
    static let buttonShadow: CGFloat = 1
    static let scrollerRadius: CGFloat = 2

    // MARK: - Spacing scale (4 / 8 / 12 / 16 / 24 / 32)

    static let space1: CGFloat = 4
    static let space2: CGFloat = 8
    static let space3: CGFloat = 12
    static let space4: CGFloat = 16
    static let space5: CGFloat = 24
    static let space6: CGFloat = 32

    // MARK: - Layout

    /// Wide enough for square tiles with padded labels (“General”, “Recording”).
    static let sidebarWidth: CGFloat = 128
    static let sidebarTileSize: CGFloat = 84
    /// Inner padding inside each sidebar tile (label must not touch the border).
    static let sidebarTilePad: CGFloat = 8
    static let sidebarIconLabelGap: CGFloat = 6
    static let sidebarTileGap: CGFloat = 8
    static let sidebarSectionGap: CGFloat = 12
    /// Footer (mark + version) height — used as ScrollView bottom inset.
    static let sidebarFooterHeight: CGFloat = 72

    static let pageTop: CGFloat = 16
    static let pageSide: CGFloat = 24
    static let pageBottom: CGFloat = 24
    /// Content column grows with the window; caps so lines stay readable.
    static let maxContentWidth: CGFloat = 880
    static let sectionGap: CGFloat = space5
    static let sectionInnerGap: CGFloat = space2
    static let titleDescGap: CGFloat = space1
    static let rowHPad: CGFloat = space4
    static let rowVPad: CGFloat = space3
    static let cardPad: CGFloat = space4
    static let gridGap: CGFloat = space3
    static let statusBarHeight: CGFloat = 24
    static let titleStripHeight: CGFloat = 38
    static let menuBarShadow: CGFloat = 4
    static let scrollerWidth: CGFloat = 8
    static let scrollerThumbMin: CGFloat = 28

    // MARK: - Type
    //
    // Chrome (Departure Mono, PostScript `DepartureMono-Regular` via ATSApplicationFontsPath):
    //   title / heading / label / number / buttons / keycaps / badges / sidebar / status
    // Long copy (SF Mono): body / caption
    // Prefer crisp pixel sizes: 11, 13, 16, 22.

    /// Departure Mono PostScript name (bundled OFL under `PromptAnnotator/Fonts/`).
    static let monoName = "DepartureMono-Regular"

    /// Primary tokens — retune here only.
    static let titleFont = mono(22)
    static let headingFont = mono(11)
    static let labelFont = mono(13)
    static let numberFont = mono(22)
    static let bodyFont = Font.system(size: 13, weight: .regular, design: .monospaced)
    static let captionFont = Font.system(size: 11, weight: .regular, design: .monospaced)

    /// Role aliases (kept so existing call sites stay compile-safe).
    static let pageTitleFont = titleFont
    static let onboardingHeroFont = mono(22)
    static let stepTitleFont = titleFont
    static let sectionTitleFont = headingFont
    static let tileTitleFont = labelFont
    static let statValueFont = numberFont
    static let rowTitleFont = labelFont
    static let eyebrowFont = headingFont
    static let statusFont = mono(11)
    static let wordmarkFont = mono(11)
    static let buttonFont = labelFont
    static let buttonSmallFont = mono(11)
    static let keycapFont = labelFont
    static let keycapCompactFont = mono(11)
    static let badgeFont = mono(11)
    static let sidebarTileLabelFont = mono(11)
    static let sidebarSectionFont = headingFont
    static let menuBarItemFont = labelFont
    static let menuBarMetaFont = captionFont
    static let microFont = mono(11)

    static func mono(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        // Weight variants are not shipped; size is what matters for motifs.
        _ = weight
        return Font.custom(monoName, size: size)
    }

    static func systemMono(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        Font.system(size: size, weight: weight, design: .monospaced)
    }

    // MARK: - Helpers

    static func color(light: String, dark: String) -> Color {
        color(light: nsColor(hex: light), dark: nsColor(hex: dark))
    }

    static func color(light: NSColor, dark: NSColor) -> Color {
        Color(nsColor: NSColor(name: nil, dynamicProvider: { appearance in
            let match = appearance.bestMatch(from: [.darkAqua, .aqua])
            return match == .darkAqua ? dark : light
        }))
    }

    static func nsColor(hex: String) -> NSColor {
        var cleaned = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.hasPrefix("#") { cleaned.removeFirst() }
        guard cleaned.count == 6, let value = UInt32(cleaned, radix: 16) else {
            return .labelColor
        }
        let r = CGFloat((value >> 16) & 0xFF) / 255
        let g = CGFloat((value >> 8) & 0xFF) / 255
        let b = CGFloat(value & 0xFF) / 255
        return NSColor(srgbRed: r, green: g, blue: b, alpha: 1)
    }

    static var windowNSColor: NSColor {
        NSColor(name: nil, dynamicProvider: { appearance in
            let match = appearance.bestMatch(from: [.darkAqua, .aqua])
            return match == .darkAqua ? nsColor(hex: "#000000") : nsColor(hex: "#FFFFFF")
        })
    }
}
