import AppKit
import Foundation

/// Disk-backed clipboard history: JSON index + image files under Application Support.
@MainActor
final class ClipboardHistoryStore: ObservableObject {
    static let shared = ClipboardHistoryStore()

    @Published private(set) var items: [ClipboardItem] = []

    /// While > 0, the watcher ignores pasteboard changes (our own paste-back / staging).
    private(set) var suppressWatcher = 0

    private let fileManager = FileManager.default
    private var folderURL: URL
    private var indexURL: URL
    private var imagesURL: URL

    init(folder: URL? = nil) {
        let root = folder ?? Self.defaultFolder()
        folderURL = root
        indexURL = root.appendingPathComponent("index.json")
        imagesURL = root.appendingPathComponent("images", isDirectory: true)
        try? fileManager.createDirectory(at: imagesURL, withIntermediateDirectories: true)
        load()
    }

    static func defaultFolder() -> URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return support.appendingPathComponent("PromptAnnotator/ClipboardHistory", isDirectory: true)
    }

    func beginOwnWrite() { suppressWatcher += 1 }
    func endOwnWrite() { suppressWatcher = max(0, suppressWatcher - 1) }

    var historyLimit: Int {
        AppSettings.shared.clipboardHistoryLimit
    }

    // MARK: - Mutations

    @discardableResult
    func ingest(
        kind: ClipboardPayloadKind,
        source: ClipboardItemSource,
        text: String?,
        imagePNG: Data?,
        filePaths: [String]?,
        fingerprint: String
    ) -> ClipboardItem? {
        if let existing = items.first(where: { $0.fingerprint == fingerprint }) {
            var moved = existing
            moved.createdAt = Date()
            items.removeAll { $0.id == existing.id }
            items.insert(moved, at: 0)
            persist()
            return moved
        }

        var imageName: String?
        if let imagePNG {
            let name = "\(UUID().uuidString).png"
            let url = imagesURL.appendingPathComponent(name)
            do {
                try imagePNG.write(to: url, options: .atomic)
                imageName = name
            } catch {
                return nil
            }
        }

        let item = ClipboardItem(
            id: UUID(),
            createdAt: Date(),
            kind: kind,
            source: source,
            text: text,
            imageFileName: imageName,
            filePaths: filePaths,
            pinned: false,
            fingerprint: fingerprint
        )
        items.insert(item, at: 0)
        trimToLimit()
        persist()
        return item
    }

    func togglePin(_ id: UUID) {
        guard let idx = items.firstIndex(where: { $0.id == id }) else { return }
        items[idx].pinned.toggle()
        sortPinnedFirst()
        persist()
    }

    func delete(_ id: UUID) {
        guard let idx = items.firstIndex(where: { $0.id == id }) else { return }
        let item = items.remove(at: idx)
        if let name = item.imageFileName {
            try? fileManager.removeItem(at: imagesURL.appendingPathComponent(name))
        }
        persist()
    }

    func clearHistory(keepingPinned: Bool = false) {
        if keepingPinned {
            let remove = items.filter { !$0.pinned }
            for item in remove {
                if let name = item.imageFileName {
                    try? fileManager.removeItem(at: imagesURL.appendingPathComponent(name))
                }
            }
            items.removeAll { !$0.pinned }
        } else {
            for item in items {
                if let name = item.imageFileName {
                    try? fileManager.removeItem(at: imagesURL.appendingPathComponent(name))
                }
            }
            items.removeAll()
        }
        persist()
    }

    func orderedForDisplay(filter: String) -> [ClipboardItem] {
        let q = filter.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let base = items
        let filtered: [ClipboardItem]
        if q.isEmpty {
            filtered = base
        } else {
            filtered = base.filter {
                $0.previewLine.lowercased().contains(q)
                    || ($0.text?.lowercased().contains(q) ?? false)
            }
        }
        return filtered.sorted { lhs, rhs in
            if lhs.pinned != rhs.pinned { return lhs.pinned && !rhs.pinned }
            return lhs.createdAt > rhs.createdAt
        }
    }

    func image(for item: ClipboardItem) -> NSImage? {
        guard let name = item.imageFileName else { return nil }
        return NSImage(contentsOf: imagesURL.appendingPathComponent(name))
    }

    // MARK: - Persistence

    private func load() {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let data = try? Data(contentsOf: indexURL),
              let decoded = try? decoder.decode([ClipboardItem].self, from: data) else {
            items = []
            return
        }
        items = decoded
        sortPinnedFirst()
    }

    private func persist() {
        try? fileManager.createDirectory(at: folderURL, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(items) else { return }
        try? data.write(to: indexURL, options: .atomic)
    }

    private func trimToLimit() {
        let limit = max(1, historyLimit)
        var pinned = items.filter(\.pinned)
        var unpinned = items.filter { !$0.pinned }
        while pinned.count + unpinned.count > limit, let drop = unpinned.popLast() {
            if let name = drop.imageFileName {
                try? fileManager.removeItem(at: imagesURL.appendingPathComponent(name))
            }
        }
        items = pinned + unpinned
        sortPinnedFirst()
    }

    private func sortPinnedFirst() {
        items.sort { lhs, rhs in
            if lhs.pinned != rhs.pinned { return lhs.pinned && !rhs.pinned }
            return lhs.createdAt > rhs.createdAt
        }
    }
}

// MARK: - Fingerprints (testable, pure)

enum ClipboardFingerprint {
    static func text(_ string: String) -> String {
        "text:" + sha256(string)
    }

    static func image(_ data: Data) -> String {
        "image:" + sha256(data)
    }

    static func files(_ paths: [String]) -> String {
        "files:" + sha256(paths.sorted().joined(separator: "\n"))
    }

    private static func sha256(_ string: String) -> String {
        sha256(Data(string.utf8))
    }

    private static func sha256(_ data: Data) -> String {
        // Lightweight FNV-1a 64 — enough for dedupe without CryptoKit dependency friction in tests.
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in data {
            hash ^= UInt64(byte)
            hash = hash &* 0x100000001b3
        }
        return String(hash, radix: 16)
    }
}
