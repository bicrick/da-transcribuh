import Foundation

/// Release page link and the running version. Update checks go through Sparkle (UpdateController).
enum ReleaseCheck {
    static let repo = URL(string: "https://github.com/bicrick/da-transcribuh/releases")!

    static func currentVersion() -> String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.9.0"
    }
}
