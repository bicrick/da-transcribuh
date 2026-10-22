import Foundation

/// Once Get Started is fully complete, Home never shows the checklist again.
/// Later regressions (revoked permission, missing model) surface in the status line.
enum HomeGetStartedStore {
    static let key = "home.getStarted.complete"

    static func isComplete(_ defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: key)
    }

    static func markComplete(_ defaults: UserDefaults = .standard) {
        defaults.set(true, forKey: key)
    }

    /// Test helper — clears the flag.
    static func reset(_ defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: key)
    }
}
