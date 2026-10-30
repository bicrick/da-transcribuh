import Foundation

/// Marketing version and build come from the Xcode project.
enum AppVersion {
    static var marketing: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.1"
    }

    static var build: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "10"
    }

    static var label: String {
        "\(marketing) (\(build))"
    }
}
