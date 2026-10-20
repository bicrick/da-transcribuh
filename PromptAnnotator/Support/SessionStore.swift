import Foundation

/// The sessions folder. The default is Documents/PromptAnnotator/Sessions.
/// A chosen folder is kept as a security-scoped bookmark.
enum SessionStore {
    private static let bookmarkKey = "sessions.bookmark"
    private static var accessed: URL?

    static func root() throws -> URL {
        let folder = resolvedFolder()
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    static func displayPath() -> String {
        abbreviate(resolvedFolder().path)
    }

    static func usesCustomFolder() -> Bool {
        UserDefaults.standard.data(forKey: bookmarkKey) != nil
    }

    static func choose(_ url: URL) throws {
        let data = try url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
        releaseAccess()
        UserDefaults.standard.set(data, forKey: bookmarkKey)
        _ = url.startAccessingSecurityScopedResource()
        accessed = url
    }

    static func reset() {
        UserDefaults.standard.removeObject(forKey: bookmarkKey)
        releaseAccess()
    }

    private static func resolvedFolder() -> URL {
        if let bookmarked = resolveBookmark() {
            return bookmarked
        }
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return documents.appendingPathComponent("PromptAnnotator/Sessions", isDirectory: true)
    }

    private static func resolveBookmark() -> URL? {
        if let accessed { return accessed }
        guard let data = UserDefaults.standard.data(forKey: bookmarkKey) else { return nil }
        var stale = false
        guard let url = try? URL(
            resolvingBookmarkData: data,
            options: .withSecurityScope,
            relativeTo: nil,
            bookmarkDataIsStale: &stale
        ) else { return nil }
        _ = url.startAccessingSecurityScopedResource()
        accessed = url
        if stale {
            try? choose(url)
        }
        return url
    }

    private static func releaseAccess() {
        accessed?.stopAccessingSecurityScopedResource()
        accessed = nil
    }

    private static func abbreviate(_ path: String) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        guard path.hasPrefix(home) else { return path }
        return "~" + path.dropFirst(home.count)
    }
}
