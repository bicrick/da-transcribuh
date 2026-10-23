import AppKit
import Foundation
import ImageIO

/// Disk-backed clipboard history: JSON index + image files under Application Support.
@MainActor
final class ClipboardHistoryStore: ObservableObject {
    static let shared = ClipboardHistoryStore()

    @Published private(set) var items: [ClipboardItem] = []

    /// While > 0, the watcher ignores pasteboard changes (our own paste-back / staging).
    private(set) var suppressWatcher = 0

    /// Fired when nested own-write suppress returns to 0 so the watcher can
    /// sync `changeCount` (sync writes finish between timer ticks).
    var onOwnWriteEnded: (() -> Void)?

    /// Test override for history limit (nil → AppSettings).
    var historyLimitOverride: Int?

    private let fileManager = FileManager.default
    private let imageCache: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        cache.countLimit = 6
        return cache
    }()
    private let thumbnailCache: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        cache.countLimit = 200
        return cache
    }()
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
        if let override = PerfSuite.clipboardRootOverride { return override }
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return support.appendingPathComponent("PromptAnnotator/ClipboardHistory", isDirectory: true)
    }

    func beginOwnWrite() { suppressWatcher += 1 }

    /// Harness only (`-DTPerfSeedClipboard`, temp store): every third item is an image.
    func perfSeed(count: Int) {
        historyLimitOverride = max(count, historyLimit)
        var index = items.count
        while items.count < count {
            index += 1
            if index % 3 == 0 {
                let png = PerfSuite.syntheticPNG(width: 1200, height: 760, seed: index)
                ingest(kind: .image, source: .pasteboard, text: nil, imagePNG: png, filePaths: nil,
                       fingerprint: ClipboardFingerprint.image(png), applicationName: "Perf")
            } else {
                let text = "item \(index) " + String(repeating: "the quick brown fox \(index % 17) ", count: 1 + index % 40)
                ingest(kind: .text, source: .pasteboard, text: text, imagePNG: nil, filePaths: nil,
                       fingerprint: ClipboardFingerprint.text(text), applicationName: "Perf")
            }
        }
    }

    func endOwnWrite() {
        let previous = suppressWatcher
        suppressWatcher = max(0, suppressWatcher - 1)
        if previous > 0, suppressWatcher == 0 {
            onOwnWriteEnded?()
        }
    }

    var historyLimit: Int {
        historyLimitOverride ?? AppSettings.shared.clipboardHistoryLimit
    }

    // MARK: - Mutations

    @discardableResult
    func ingest(
        kind: ClipboardPayloadKind,
        source: ClipboardItemSource,
        text: String?,
        imagePNG: Data?,
        filePaths: [String]?,
        fingerprint: String,
        applicationName: String? = nil,
        imageWidth: Int? = nil,
        imageHeight: Int? = nil
    ) -> ClipboardItem? {
        let now = Date()
        if let existing = items.first(where: { $0.fingerprint == fingerprint }) {
            var moved = existing
            moved.lastCopiedAt = now
            moved.createdAt = now
            moved.copyCount += 1
            if let applicationName, !applicationName.isEmpty {
                moved.applicationName = applicationName
            }
            items.removeAll { $0.id == existing.id }
            items.insert(moved, at: 0)
            persist()
            return moved
        }

        var imageName: String?
        var width = imageWidth
        var height = imageHeight
        if let imagePNG {
            let name = "\(UUID().uuidString).png"
            let url = imagesURL.appendingPathComponent(name)
            do {
                try imagePNG.write(to: url, options: .atomic)
                imageName = name
                if width == nil || height == nil, let image = NSImage(data: imagePNG) {
                    width = Int(image.size.width)
                    height = Int(image.size.height)
                }
            } catch {
                return nil
            }
        }

        let item = ClipboardItem(
            id: UUID(),
            createdAt: now,
            kind: kind,
            source: source,
            text: text,
            imageFileName: imageName,
            filePaths: filePaths,
            pinned: false,
            fingerprint: fingerprint,
            applicationName: applicationName,
            firstCopiedAt: now,
            lastCopiedAt: now,
            copyCount: 1,
            imageWidth: width,
            imageHeight: height
        )
        items.insert(item, at: 0)
        trimToLimit()
        persist()
        return item
    }

    /// Ingests one captured pasteboard payload. Mixed copies become one row that
    /// keeps both the text and the image.
    @discardableResult
    func ingest(
        payload: ClipboardCapturePayload,
        source: ClipboardItemSource,
        applicationName: String?
    ) -> ClipboardItem? {
        switch payload {
        case let .files(paths):
            return ingest(kind: .fileURL, source: source, text: paths.joined(separator: "\n"),
                          imagePNG: nil, filePaths: paths, fingerprint: ClipboardFingerprint.files(paths),
                          applicationName: applicationName)
        case let .image(png):
            return ingest(kind: .image, source: source, text: nil, imagePNG: png, filePaths: nil,
                          fingerprint: ClipboardFingerprint.image(png), applicationName: applicationName)
        case let .text(text):
            return ingest(kind: .text, source: source, text: text, imagePNG: nil, filePaths: nil,
                          fingerprint: ClipboardFingerprint.text(text), applicationName: applicationName)
        case let .mixed(text, png):
            return ingest(kind: .text, source: source, text: text, imagePNG: png, filePaths: nil,
                          fingerprint: ClipboardFingerprint.mixed(text: text, png: png),
                          applicationName: applicationName)
        }
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

    func clearHistory(keepingPinned: Bool = true) {
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
        let settings = AppSettings.shared
        let base = items
        let filtered: [ClipboardItem]
        if q.isEmpty {
            filtered = base
        } else {
            filtered = base.filter {
                $0.previewLine.lowercased().contains(q)
                    || ($0.text?.lowercased().contains(q) ?? false)
                    || ($0.applicationName?.lowercased().contains(q) ?? false)
                    || ($0.pinTitle?.lowercased().contains(q) ?? false)
            }
        }
        let pinFirst = settings.clipboardPinEdge == .top
        let mode = settings.clipboardSortMode
        return filtered.sorted { lhs, rhs in
            if lhs.pinned != rhs.pinned {
                return pinFirst ? (lhs.pinned && !rhs.pinned) : (!lhs.pinned && rhs.pinned)
            }
            switch mode {
            case .lastCopy: return lhs.lastCopiedAt > rhs.lastCopiedAt
            case .firstCopy: return lhs.firstCopiedAt > rhs.firstCopiedAt
            case .copyCount: return lhs.copyCount > rhs.copyCount
            }
        }
    }

    /// Full-size image for the preview. Cached: the panel body asks again on every
    /// selection change, and re-reading PNGs from disk per arrow press cost ~58ms.
    func image(for item: ClipboardItem) -> NSImage? {
        guard let name = item.imageFileName else { return nil }
        let key = name as NSString
        if let hit = imageCache.object(forKey: key) { return hit }
        guard let image = NSImage(contentsOf: imagesURL.appendingPathComponent(name)) else { return nil }
        imageCache.setObject(image, forKey: key)
        return image
    }

    /// The stored PNG bytes, for paste-back without a decode and re-encode.
    func imagePNGData(for item: ClipboardItem) -> Data? {
        guard let name = item.imageFileName else { return nil }
        return try? Data(contentsOf: imagesURL.appendingPathComponent(name))
    }

    // Row thumbnails are downsampled once with ImageIO to `maxHeight` points at 2x,
    // so list rows never decode or rescale a full screenshot while scrolling.

    /// Cache-only lookup: never touches disk.
    func cachedThumbnail(for item: ClipboardItem, maxHeight: CGFloat) -> NSImage? {
        guard let name = item.imageFileName else { return nil }
        return thumbnailCache.object(forKey: Self.thumbnailKey(name, maxHeight) as NSString)
    }

    /// Decodes off the main thread and caches. The panel builds every row on first
    /// open (DTScrollView measures its LazyVStack in full), and decoding ~70
    /// thumbnails synchronously there was most of a ~700 ms first open.
    func loadThumbnail(for item: ClipboardItem, maxHeight: CGFloat) async -> NSImage? {
        if let hit = cachedThumbnail(for: item, maxHeight: maxHeight) { return hit }
        guard let request = thumbnailRequest(for: item, maxHeight: maxHeight) else { return nil }
        let image = await Task.detached(priority: .userInitiated) {
            Self.decodeThumbnail(request)
        }.value
        if let image {
            thumbnailCache.setObject(image, forKey: request.key as NSString)
        }
        return image
    }

    struct ThumbnailRequest: Sendable {
        var url: URL
        var maxHeight: CGFloat
        var key: String
    }

    private func thumbnailRequest(for item: ClipboardItem, maxHeight: CGFloat) -> ThumbnailRequest? {
        guard let name = item.imageFileName else { return nil }
        return ThumbnailRequest(
            url: imagesURL.appendingPathComponent(name),
            maxHeight: maxHeight,
            key: Self.thumbnailKey(name, maxHeight)
        )
    }

    private nonisolated static func thumbnailKey(_ name: String, _ maxHeight: CGFloat) -> String {
        "\(name)@\(Int(maxHeight))"
    }

    nonisolated static func decodeThumbnail(_ request: ThumbnailRequest) -> NSImage? {
        guard let source = CGImageSourceCreateWithURL(request.url as CFURL, nil) else { return nil }
        let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        let pixelW = (props?[kCGImagePropertyPixelWidth] as? CGFloat) ?? 0
        let pixelH = (props?[kCGImagePropertyPixelHeight] as? CGFloat) ?? 0
        let scale = pixelH > 0 ? min(1, (request.maxHeight * 2) / pixelH) : 1
        let maxPixel = max(1, max(pixelW, pixelH) * scale)
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }
        return NSImage(cgImage: cg, size: NSSize(width: CGFloat(cg.width) / 2, height: CGFloat(cg.height) / 2))
    }

    /// History folder (index + images). Read-only for off-main measurement.
    var storageFolder: URL { folderURL }

    /// Approximate on-disk size of the history folder (index + images).
    func diskUsageBytes() -> Int64 {
        Self.diskUsageBytes(at: folderURL)
    }

    /// Directory walk; safe off the main actor (touches only the file system).
    nonisolated static func diskUsageBytes(at folder: URL) -> Int64 {
        let fileManager = FileManager.default
        var total: Int64 = 0
        let urls = (try? fileManager.contentsOfDirectory(
            at: folder,
            includingPropertiesForKeys: [.fileSizeKey, .isDirectoryKey],
            options: [.skipsHiddenFiles]
        )) ?? []
        for url in urls {
            if let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey]),
               values.isDirectory == true {
                let nested = (try? fileManager.contentsOfDirectory(
                    at: url,
                    includingPropertiesForKeys: [.fileSizeKey],
                    options: [.skipsHiddenFiles]
                )) ?? []
                for child in nested {
                    if let size = try? child.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                        total += Int64(size)
                    }
                }
            } else if let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                total += Int64(size)
            }
        }
        return total
    }

    func updatePinMetadata(id: UUID, title: String?, key: String?) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].pinTitle = title?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        let trimmed = key?.trimmingCharacters(in: .whitespacesAndNewlines)
        items[index].pinKey = trimmed.flatMap { $0.isEmpty ? nil : String($0.prefix(1)).uppercased() }
        persist()
    }

    func clearHistoryFully(clearSystem: Bool) {
        clearHistory(keepingPinned: false)
        if clearSystem {
            NSPasteboard.general.clearContents()
        }
    }

    // MARK: - Persistence

    private func load() {
        Self.flushPendingWrites()
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

    /// One serial queue for every store, so writes land in order and a store that
    /// loads the same folder sees the last write (`load` waits on it).
    nonisolated static let persistQueue = DispatchQueue(label: "clipboard.persist", qos: .utility)

    /// Encodes and writes the index off the main thread. The pretty-printed,
    /// sorted-keys encode of a 200-item index ran on main after every copy.
    private func persist() {
        let snapshot = items
        let folder = folderURL
        let index = indexURL
        Self.persistQueue.async {
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            guard let data = try? encoder.encode(snapshot) else { return }
            try? data.write(to: index, options: .atomic)
        }
    }

    /// Blocks until queued index writes are on disk (quit, tests).
    nonisolated static func flushPendingWrites() {
        persistQueue.sync {}
    }

    private func trimToLimit() {
        let limit = max(1, historyLimit)
        var pinned = items.filter(\.pinned)
        var unpinned = items.filter { !$0.pinned }.sorted { $0.lastCopiedAt > $1.lastCopiedAt }
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
            return lhs.lastCopiedAt > rhs.lastCopiedAt
        }
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}

// MARK: - Fingerprints (testable, pure)

enum ClipboardFingerprint {
    static func text(_ string: String) -> String {
        "text:" + sha256(string)
    }

    static func image(_ data: Data) -> String {
        "image:" + sha256(data)
    }

    /// Text and image from one copy. Differs from either part alone, so a later
    /// text-only copy of the same words is its own row.
    static func mixed(text: String, png: Data) -> String {
        "mixed:" + sha256(text) + ":" + sha256(png)
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
