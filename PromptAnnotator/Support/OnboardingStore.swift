import Foundation

/// First launch walks through permissions, the shortcut, the speech model, and a practice take.
enum OnboardingStore {
    static let key = "onboarding.finished"

    static func isFinished(_ defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: key)
    }

    static func finish(_ defaults: UserDefaults = .standard) {
        defaults.set(true, forKey: key)
    }
}
