import Foundation

/// First launch walks through permissions, the shortcut, the speech model, and a practice take.
///
/// Turning on Screen Recording makes macOS quit and reopen the app. The current
/// step is saved on every change so a relaunch lands back on that step (usually
/// Permissions) instead of starting over at Welcome.
enum OnboardingStore {
    static let key = "onboarding.finished"
    static let stepKey = "onboarding.step"

    static func isFinished(_ defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: key)
    }

    static func finish(_ defaults: UserDefaults = .standard) {
        defaults.set(true, forKey: key)
        clearStep(defaults)
    }

    /// Remembers where a first-run user is. Ignored once setup is finished, so
    /// replaying Welcome from Settings never leaves a stale step behind.
    static func saveStep(_ step: OnboardingStep, _ defaults: UserDefaults = .standard) {
        guard !isFinished(defaults) else { return }
        if defaults.object(forKey: stepKey) as? Int == step.rawValue { return }
        defaults.set(step.rawValue, forKey: stepKey)
    }

    static func savedStep(_ defaults: UserDefaults = .standard) -> OnboardingStep? {
        guard let raw = defaults.object(forKey: stepKey) as? Int else { return nil }
        return OnboardingStep(rawValue: raw)
    }

    static func clearStep(_ defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: stepKey)
    }

    /// Step the welcome window opens on: the saved step while setup is unfinished,
    /// otherwise Welcome. An unknown saved value (older or newer build) falls back to Welcome.
    static func resumeStep(_ defaults: UserDefaults = .standard) -> OnboardingStep {
        guard !isFinished(defaults) else { return .welcome }
        return savedStep(defaults) ?? .welcome
    }
}
