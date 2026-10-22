import AppKit
import SwiftUI

/// "Ink" palette — warm paper neutrals + logo red. Asset-free dynamic light/dark.
enum Ink {
    // MARK: - Dynamic colors

    static let accent = color(light: "#E5432F", dark: "#FF6A55")
    static let accentSoft = color(
        light: NSColor(srgbRed: 229 / 255, green: 67 / 255, blue: 47 / 255, alpha: 0.10),
        dark: NSColor(srgbRed: 255 / 255, green: 106 / 255, blue: 85 / 255, alpha: 0.14)
    )
    static let sidebarSelection = color(
        light: NSColor(srgbRed: 229 / 255, green: 67 / 255, blue: 47 / 255, alpha: 0.12),
        dark: NSColor(srgbRed: 255 / 255, green: 106 / 255, blue: 85 / 255, alpha: 0.18)
    )
    static let window = color(light: "#F6F2EC", dark: "#1D1A17")
    static let card = color(light: "#FFFDFA", dark: "#26221F")
    static let field = color(light: "#FBF7F1", dark: "#2B2723")
    static let label = color(light: "#1F1A16", dark: "#F4EEE7")
    static let secondary = color(light: "#6E655C", dark: "#A79E94")
    static let tertiary = color(light: "#A39A90", dark: "#6F675F")
    static let hairline = color(
        light: NSColor(srgbRed: 70 / 255, green: 45 / 255, blue: 20 / 255, alpha: 0.10),
        dark: NSColor(srgbRed: 255 / 255, green: 236 / 255, blue: 215 / 255, alpha: 0.08)
    )
    static let borderStrong = color(
        light: NSColor(srgbRed: 70 / 255, green: 45 / 255, blue: 20 / 255, alpha: 0.16),
        dark: NSColor(srgbRed: 255 / 255, green: 236 / 255, blue: 215 / 255, alpha: 0.14)
    )
    static let fill = color(
        light: NSColor(srgbRed: 70 / 255, green: 45 / 255, blue: 20 / 255, alpha: 0.06),
        dark: NSColor(srgbRed: 255 / 255, green: 236 / 255, blue: 215 / 255, alpha: 0.06)
    )
    static let track = color(
        light: NSColor(srgbRed: 70 / 255, green: 45 / 255, blue: 20 / 255, alpha: 0.09),
        dark: NSColor(srgbRed: 255 / 255, green: 236 / 255, blue: 215 / 255, alpha: 0.10)
    )
    static let meter = color(light: "#3A332D", dark: "#E9E1D8")
    static let success = color(light: "#2F8F5B", dark: "#4CC38A")
    static let error = color(light: "#D93025", dark: "#FF6B5E")
    static let keycap = color(light: "#FFFFFF", dark: "#34302C")
    static let onAccent = Color.white
    static let sidebar = color(
        light: NSColor(srgbRed: 250 / 255, green: 246 / 255, blue: 240 / 255, alpha: 0.92),
        dark: NSColor(srgbRed: 36 / 255, green: 32 / 255, blue: 29 / 255, alpha: 0.92)
    )

    // MARK: - Radii

    static let cardRadius: CGFloat = 12
    static let tileRadius: CGFloat = 14
    static let buttonRadius: CGFloat = 7
    static let buttonLargeRadius: CGFloat = 9
    static let fieldRadius: CGFloat = 7
    static let sidebarRowRadius: CGFloat = 8
    static let keycapRadius: CGFloat = 8

    // MARK: - Layout

    static let sidebarWidth: CGFloat = 220
    static let pageTop: CGFloat = 52
    static let pageSide: CGFloat = 36
    static let pageBottom: CGFloat = 36
    static let maxContentWidth: CGFloat = 680
    static let sectionGap: CGFloat = 28
    static let sectionInnerGap: CGFloat = 10
    static let rowHPad: CGFloat = 16
    static let rowVPad: CGFloat = 14
    static let gridGap: CGFloat = 12

    // MARK: - Type

    static let pageTitleFont = Font.system(size: 28, weight: .bold)
    static let onboardingHeroFont = Font.system(size: 30, weight: .bold)
    static let stepTitleFont = Font.system(size: 24, weight: .bold)
    static let sectionTitleFont = Font.system(size: 15, weight: .semibold)
    static let tileTitleFont = Font.system(size: 16, weight: .bold)
    static let statValueFont = Font.system(size: 26, weight: .bold)
    static let rowTitleFont = Font.system(size: 13, weight: .semibold)
    static let bodyFont = Font.system(size: 13, weight: .regular)
    static let captionFont = Font.system(size: 12, weight: .regular)
    static let eyebrowFont = Font.system(size: 11, weight: .bold)

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
            return match == .darkAqua ? nsColor(hex: "#1D1A17") : nsColor(hex: "#F6F2EC")
        })
    }
}
