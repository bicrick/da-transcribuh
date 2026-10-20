import Foundation

enum ReleaseCheck {
    static let repo = URL(string: "https://github.com/bicrick/prompt-annotator/releases")!

    static func currentVersion() -> String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
    }

    static func lookUp() async -> String {
        let current = currentVersion()
        guard let url = URL(string: "https://api.github.com/repos/bicrick/prompt-annotator/releases/latest") else {
            return "This build is \(current)."
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 12
        request.setValue("PromptAnnotator", forHTTPHeaderField: "User-Agent")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            if code == 404 {
                return "No release has been published yet. This build is \(current)."
            }
            guard code == 200,
                  let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let tag = json["tag_name"] as? String else {
                return "Couldn't read the latest release. This build is \(current)."
            }
            let latest = tag.trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
            if latest == current {
                return "You're on the latest release (\(current))."
            }
            return "\(tag) is on GitHub. This build is \(current)."
        } catch {
            return "Couldn't reach GitHub. This build is \(current)."
        }
    }
}
