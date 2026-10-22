import AppKit
import SwiftUI

/// "da transcribuh" chrome — MS Paint retro: flat color accents, chunky outlines,
/// hard offset shadows, Departure Mono labels. Light stays white; dark is charcoal
/// (not pure black) so the Paint accents still pop.
/// Kept under the `Ink` name so existing call sites stay compile-safe.
enum Ink {
    // MARK: - Dynamic surfaces (light / dark)

    /// Charcoal dark (~#1E1E1E) — softer than pure black.
    static let window = color(light: "#FFFFFF", dark: "#1E1E1E")
    static let canvas = color(light: "#FFFFFF", dark: "#1E1E1E")
    static let label = color(light: "#000000", dark: "#EDEDED")
    static let onAccent = color(light: "#FFFFFF", dark: "#1E1E1E")
    /// Primary fill / border rule.
    static let accent = label
    static let accentSoft = fill
    static let sidebarSelection = label
    static let hairline = color(light: "#C0C0C0", dark: "#3A3A3A")
    static let borderStrong = label
    static let fill = color(light: "#F0F0F0", dark: "#2B2B2B")
    static let track = hairline
    static let meter = label
    static let secondary = color(light: "#666666", dark: "#A8A8A8")
    static let tertiary = color(light: "#999999", dark: "#6E6E6E")
    static let field = window
    static let card = window
    static let keycap = window
    static let sidebar = color(light: "#F7F7F7", dark: "#232323")

    // MARK: - Classic MS Paint flat swatches (Win95/98 era)

    static let paintBlack = color(light: "#000000", dark: "#000000")
    static let paintWhite = color(light: "#FFFFFF", dark: "#FFFFFF")
    static let paintGray = color(light: "#7F7F7F", dark: "#7F7F7F")
    static let paintSilver = color(light: "#C3C3C3", dark: "#C3C3C3")
    static let paintRed = color(light: "#ED1C24", dark: "#ED1C24")
    static let paintYellow = color(light: "#FFF200", dark: "#FFF200")
    static let paintGreen = color(light: "#22B14C", dark: "#22B14C")
    static let paintBlue = color(light: "#3F48CC", dark: "#3F48CC")
    static let paintCyan = color(light: "#00A2E8", dark: "#00A2E8")
    static let paintMagenta = color(light: "#A349A4", dark: "#A349A4")
    static let paintOrange = color(light: "#FF7F27", dark: "#FF7F27")
    static let paintBrown = color(light: "#B97A57", dark: "#B97A57")
    static let paintLime = color(light: "#B5E61D", dark: "#B5E61D")
    static let paintPink = color(light: "#FFAEC9", dark: "#FFAEC9")
    static let paintNavy = color(light: "#1E3A8A", dark: "#1E3A8A")
    static let paintTeal = color(light: "#008080", dark: "#008080")

    /// Ordered toolbox / status-bar palette strip.
    static var paintSwatches: [Color] {
        [
            paintBlack, paintGray, paintSilver, paintWhite,
            paintRed, paintOrange, paintYellow, paintLime,
            paintGreen, paintTeal, paintCyan, paintBlue,
            paintNavy, paintMagenta, paintPink, paintBrown,
        ]
    }

    /// Per-sidebar-page accent (icon / pressed fill hint).
    static func toolAccent(for page: SettingsPage) -> Color {
        switch page {
        case .home: return paintBlue
        case .history: return paintOrange
        case .recording: return paintRed
        case .model: return paintMagenta
        case .configuration: return paintGray
        case .sound: return paintCyan
        case .performance: return paintGreen
        }
    }

    /// Recording-active marker (status / island).
    static let record = paintRed
    static let success = paintGreen
    static let error = paintRed

    // MARK: - Radii / stroke

    static let cardRadius: CGFloat = 2
    static let tileRadius: CGFloat = 2
    static let buttonRadius: CGFloat = 2
    static let buttonLargeRadius: CGFloat = 2
    static let fieldRadius: CGFloat = 2
    static let sidebarRowRadius: CGFloat = 2
    static let keycapRadius: CGFloat = 2
    static let lineWidth: CGFloat = 1
    static let selectedBorder: CGFloat = 2
    static let hardShadow: CGFloat = 3
    static let buttonShadow: CGFloat = 2
    static let scrollerRadius: CGFloat = 1

    // MARK: - Spacing scale (airier Paint layout)

    static let space1: CGFloat = 4
    static let space2: CGFloat = 8
    static let space3: CGFloat = 12
    static let space4: CGFloat = 16
    static let space5: CGFloat = 24
    static let space6: CGFloat = 32
    static let space7: CGFloat = 48

    // MARK: - Layout

    /// Paint toolbox column — roomy tiles, big icons.
    static let sidebarWidth: CGFloat = 148
    static let sidebarTileSize: CGFloat = 72
    /// Equal left/right margin around a 72px tile in a 148px column.
    static let sidebarSideMargin: CGFloat = (sidebarWidth - sidebarTileSize) / 2
    static let sidebarTilePad: CGFloat = 6
    static let sidebarIconSize: CGFloat = 28
    /// Chunky SF Symbol weight inside the colored chip.
    static let sidebarSymbolPointSize: CGFloat = 16
    static let sidebarIconLabelGap: CGFloat = 4
    static let sidebarTileGap: CGFloat = 10
    static let sidebarSectionGap: CGFloat = 16
    static let sidebarFooterHeight: CGFloat = 80
    /// Tip row: readable icon in a Paint color square.
    static let tipIconSize: CGFloat = 48
    static let tipSymbolPointSize: CGFloat = 22

    static let pageTop: CGFloat = 28
    static let pageSide: CGFloat = 36
    static let pageBottom: CGFloat = 36
    static let maxContentWidth: CGFloat = 920
    static let sectionGap: CGFloat = space6
    static let sectionInnerGap: CGFloat = space3
    static let titleDescGap: CGFloat = space2
    static let rowHPad: CGFloat = space4
    static let rowVPad: CGFloat = space3
    static let cardPad: CGFloat = space5
    static let gridGap: CGFloat = space4
    static let statusBarHeight: CGFloat = 28
    static let titleStripHeight: CGFloat = 40
    static let menuBarShadow: CGFloat = 4
    /// Thin, inset scroller — only obvious on hover.
    static let scrollerWidth: CGFloat = 5
    static let scrollerThumbMin: CGFloat = 24
    static let scrollerInset: CGFloat = 3
    /// Sidebar rail sits inside the right tile margin so the thumb never kisses a tile.
    static let sidebarScrollerInset: CGFloat = 8

    // MARK: - Type
    //
    // Chrome: Departure Mono (PostScript `DepartureMono-Regular`, also try family name).
    // Body/caption: SF Mono via `.system(design: .monospaced)`.
    // NEVER fall back to proportional sans for chrome / wordmark.

    /// Canonical PostScript name (fontTools nameID 6).
    static let monoName = "DepartureMono-Regular"

    static let titleFont = mono(22)
    static let headingFont = mono(11)
    static let labelFont = mono(13)
    static let numberFont = mono(28)
    static let bodyFont = Font.system(size: 13, weight: .regular, design: .monospaced)
    static let captionFont = Font.system(size: 11, weight: .regular, design: .monospaced)

    static let pageTitleFont = titleFont
    static let onboardingHeroFont = mono(22)
    static let stepTitleFont = titleFont
    static let sectionTitleFont = headingFont
    static let tileTitleFont = labelFont
    static let statValueFont = numberFont
    static let rowTitleFont = labelFont
    static let eyebrowFont = headingFont
    static let statusFont = mono(11)
    static let wordmarkFont = mono(12)
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

    /// Departure Mono for chrome. Falls back to **system monospaced only** — never proportional.
    static func mono(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        _ = weight
        for name in InkFontRegistrar.candidateNames {
            if NSFont(name: name, size: size) != nil {
                return Font.custom(name, size: size)
            }
        }
        return Font.system(size: size, weight: .regular, design: .monospaced)
    }

    static var monoIsRegistered: Bool {
        InkFontRegistrar.isDepartureAvailable
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
            return match == .darkAqua ? nsColor(hex: "#1E1E1E") : nsColor(hex: "#FFFFFF")
        })
    }
}
