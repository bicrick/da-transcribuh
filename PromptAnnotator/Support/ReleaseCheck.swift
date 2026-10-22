import Foundation

enum ReleaseCheck {
    static let repo = URL(string: "https://github.com/bicrick/da-transcribuh/releases")!

    static func currentVersion() -> String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.9.0"
    }

    static func lookUp() async -> String {
        let current = currentVersion()
        guard let url = URL(string: "https://api.github.com/repos/bicrick/da-transcribuh/releases/latest") else {
            return "This build is \(AppVersion.label)."
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 12
        request.setValue("da-transcribuh", forHTTPHeaderField: "User-Agent")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            if code == 404 {
                return "No release has been published yet. This build is \(AppVersion.label)."
            }
            guard code == 200,
                  let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let tag = json["tag_name"] as? String else {
                return "Couldn't read the latest release. This build is \(AppVersion.label)."
            }
            let latest = tag.trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
            if latest == current {
                return "You're on the latest release (\(AppVersion.label))."
            }
            return "\(tag) is on GitHub. This build is \(AppVersion.label)."
        } catch {
            return "Couldn't reach GitHub. This build is \(AppVersion.label)."
        }
    }
}
