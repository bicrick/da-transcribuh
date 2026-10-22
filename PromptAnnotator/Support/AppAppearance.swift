import AppKit
import SwiftUI

/// Light / dark / system appearance for Settings, menu-bar, onboarding, and Ink chrome.
/// Applied via `NSApp.appearance` so dynamic Ink colors (including island / annotate) re-resolve.
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

    var preferredColorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }

    var next: AppAppearance {
        let all = Self.allCases
        guard let index = all.firstIndex(of: self) else { return .system }
        return all[(index + 1) % all.count]
    }

    /// Apply to the whole app via `NSApp.appearance`.
    @MainActor
    func applyToApp() {
        switch self {
        case .system:
            NSApp.appearance = nil
        case .light:
            NSApp.appearance = NSAppearance(named: .aqua)
        case .dark:
            NSApp.appearance = NSAppearance(named: .darkAqua)
        }
        // Refresh Settings window background so Ink dynamic colors re-resolve.
        SettingsPresenter.shared.applyChrome()
    }

    static func stored(_ raw: String?) -> AppAppearance {
        AppAppearance(rawValue: raw ?? "") ?? .system
    }
}
