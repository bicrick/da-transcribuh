import Foundation

/// Marketing version comes from the build. The channel stays beta until 1.0.
enum AppVersion {
    static let channel = "beta"

    static var marketing: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.9.1"
    }

    static var build: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "3"
    }

    static var label: String {
        "\(marketing) \(channel) (\(build))"
    }
}
