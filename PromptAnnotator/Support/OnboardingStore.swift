import Foundation

/// First launch walks through permissions, the shortcut, and how a session works.
enum OnboardingStore {
    static let key = "onboarding.finished"

    static func isFinished(_ defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: key)
    }

    static func finish(_ defaults: UserDefaults = .standard) {
        defaults.set(true, forKey: key)
    }
}
