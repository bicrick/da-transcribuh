import AppKit
import SwiftUI

/// Light / dark / system appearance for Settings, menu-bar, onboarding, and Ink chrome.
///
/// **One source of truth:** `AppSettings.appearance` → `NSApp.appearance`.
/// Ink tokens resolve via `NSColor(name:dynamicProvider:)` against the effective AppKit
/// appearance. Do **not** also apply `.preferredColorScheme` on SwiftUI roots — that
/// double-drives the tree (flicker, half-switched chrome, sticky segment selection).
enum AppAppearance: String, CaseIterable, Identifiable, Codable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }

    /// Compact menu-bar label, e.g. `theme: dark`.
    var menuLabel: String {
        "theme: \(rawValue)"
    }

    var next: AppAppearance {
        let all = Self.allCases
        guard let index = all.firstIndex(of: self) else { return .system }
        return all[(index + 1) % all.count]
    }

    /// AppKit appearance to install on `NSApp`. `nil` follows the OS (System).
    var nsAppearance: NSAppearance? {
        switch self {
        case .system: return nil
        case .light: return NSAppearance(named: .aqua)
        case .dark: return NSAppearance(named: .darkAqua)
        }
    }

    /// Apply to the whole app via `NSApp.appearance` only.
    @MainActor
    func applyToApp() {
        NSApp.appearance = nsAppearance
    }

    static func stored(_ raw: String?) -> AppAppearance {
        AppAppearance(rawValue: raw ?? "") ?? .system
    }
}
