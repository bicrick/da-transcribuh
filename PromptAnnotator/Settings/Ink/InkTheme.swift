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

    // MARK: - Layout

    /// Narrow enough for one centered tile column (~72pt tiles + padding).
    static let sidebarWidth: CGFloat = 108
    /// Breathing room below title-bar safe area.
    static let pageTop: CGFloat = 22
    static let pageSide: CGFloat = 28
    static let pageBottom: CGFloat = 28
    static let maxContentWidth: CGFloat = 660
    static let sectionGap: CGFloat = 24
    static let sectionInnerGap: CGFloat = 8
    static let rowHPad: CGFloat = 14
    static let rowVPad: CGFloat = 12
    static let gridGap: CGFloat = 10
    static let statusBarHeight: CGFloat = 24
    static let sidebarTileSize: CGFloat = 72

    // MARK: - Type

    /// Departure Mono PostScript name (bundled OFL).
    static let monoName = "DepartureMono-Regular"

    static let pageTitleFont = Font.system(size: 22, weight: .bold)
    static let onboardingHeroFont = Font.system(size: 28, weight: .bold)
    static let stepTitleFont = Font.system(size: 22, weight: .bold)
    static let sectionTitleFont = Font.system(size: 11, weight: .bold)
    static let tileTitleFont = Font.system(size: 15, weight: .semibold)
    static let statValueFont = Font.system(size: 26, weight: .bold)
    static let rowTitleFont = Font.system(size: 13, weight: .semibold)
    static let bodyFont = Font.system(size: 13, weight: .regular)
    static let captionFont = Font.system(size: 12, weight: .regular)
    static let eyebrowFont = Font.system(size: 11, weight: .bold)
    static let statusFont = Font.custom(monoName, size: 11)
    static let wordmarkFont = Font.custom(monoName, size: 11)

    static func mono(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        // Weight variants are not shipped; size is what matters for motifs.
        _ = weight
        return Font.custom(monoName, size: size)
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
