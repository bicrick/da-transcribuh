import AppKit
import ScreenCaptureKit

/// Cached `SCShareableContent` so region snips during recording do not re-enumerate
/// every window on every shot. Invalidated on display configuration changes and
/// when a session explicitly asks for a refresh.
actor ShareableContentCache {
    static let shared = ShareableContentCache()

    private var cached: SCShareableContent?
    private var inFlight: Task<SCShareableContent, Error>?

    func content(forceRefresh: Bool = false) async throws -> SCShareableContent {
        if forceRefresh {
            cached = nil
        }
        if let cached {
            return cached
        }
        if let inFlight {
            return try await inFlight.value
        }
        let task = Task<SCShareableContent, Error> {
            try await CapturePerf.intervalAsync(.shareableContent) {
                try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            }
        }
        inFlight = task
        do {
            let content = try await task.value
            cached = content
            inFlight = nil
            return content
        } catch {
            inFlight = nil
            throw error
        }
    }

    func invalidate() {
        // Drop the cache only — do not cancel an in-flight enumeration a snip may be awaiting.
        cached = nil
    }
}

/// Wires display-change notifications into `ShareableContentCache` (AppKit → actor).
enum ShareableContentCacheWatcher {
    private static var observer: NSObjectProtocol?
    private static let lock = NSLock()

    static func installIfNeeded() {
        lock.lock()
        defer { lock.unlock() }
        guard observer == nil else { return }
        observer = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { _ in
            Task { await ShareableContentCache.shared.invalidate() }
        }
    }

    static func invalidate() {
        Task { await ShareableContentCache.shared.invalidate() }
    }
}
