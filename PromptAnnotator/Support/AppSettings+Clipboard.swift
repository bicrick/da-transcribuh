import Foundation

extension AppSettings {
    // MARK: - Clipboard preference keys

    enum ClipboardKeys {
        static let pasteAutomatically = "clipboard.pasteAutomatically"
        static let pasteWithoutFormatting = "clipboard.pasteWithoutFormatting"
        static let saveFiles = "clipboard.saveFiles"
        static let saveImages = "clipboard.saveImages"
        static let saveText = "clipboard.saveText"
        static let sortMode = "clipboard.sortMode"
        static let popupPosition = "clipboard.popupPosition"
        static let pinEdge = "clipboard.pinEdge"
        static let imageHeight = "clipboard.imageHeight"
        static let previewDelayMs = "clipboard.previewDelayMs"
        static let showSearchField = "clipboard.showSearchField"
        static let showFooter = "clipboard.showFooter"
        static let ignoredApps = "clipboard.ignoredApps"
        static let ignoreConcealed = "clipboard.ignoreConcealed"
        static let capturePaused = "clipboard.capturePaused"
        static let clearOnQuit = "clipboard.clearOnQuit"
        static let clearSystemClipboard = "clipboard.clearSystemClipboard"
    }

    func loadClipboardPreferences() {
        clipboardPasteAutomatically = defaults.object(forKey: ClipboardKeys.pasteAutomatically) as? Bool ?? true
        clipboardPasteWithoutFormatting = defaults.bool(forKey: ClipboardKeys.pasteWithoutFormatting)
        clipboardSaveFiles = defaults.object(forKey: ClipboardKeys.saveFiles) as? Bool ?? true
        clipboardSaveImages = defaults.object(forKey: ClipboardKeys.saveImages) as? Bool ?? true
        clipboardSaveText = defaults.object(forKey: ClipboardKeys.saveText) as? Bool ?? true
        clipboardSortMode = ClipboardSortMode(rawValue: defaults.string(forKey: ClipboardKeys.sortMode) ?? "") ?? .lastCopy
        clipboardPopupPosition = ClipboardPopupPosition(rawValue: defaults.string(forKey: ClipboardKeys.popupPosition) ?? "") ?? .cursor
        clipboardPinEdge = ClipboardPinEdge(rawValue: defaults.string(forKey: ClipboardKeys.pinEdge) ?? "") ?? .top
        let height = defaults.object(forKey: ClipboardKeys.imageHeight) as? Double ?? 40
        clipboardImageHeight = min(120, max(24, height))
        let delay = defaults.object(forKey: ClipboardKeys.previewDelayMs) as? Int ?? 400
        clipboardPreviewDelayMs = min(2000, max(0, delay))
        clipboardShowSearchField = defaults.object(forKey: ClipboardKeys.showSearchField) as? Bool ?? true
        clipboardShowFooter = defaults.object(forKey: ClipboardKeys.showFooter) as? Bool ?? true
        clipboardIgnoredApps = defaults.stringArray(forKey: ClipboardKeys.ignoredApps) ?? []
        clipboardIgnoreConcealed = defaults.object(forKey: ClipboardKeys.ignoreConcealed) as? Bool ?? true
        clipboardCapturePaused = defaults.bool(forKey: ClipboardKeys.capturePaused)
        clipboardClearOnQuit = defaults.bool(forKey: ClipboardKeys.clearOnQuit)
        clipboardClearSystemClipboard = defaults.bool(forKey: ClipboardKeys.clearSystemClipboard)
    }

    func setClipboardPasteAutomatically(_ enabled: Bool) {
        clipboardPasteAutomatically = enabled
        persist(ClipboardKeys.pasteAutomatically, enabled)
    }

    func setClipboardPasteWithoutFormatting(_ enabled: Bool) {
        clipboardPasteWithoutFormatting = enabled
        persist(ClipboardKeys.pasteWithoutFormatting, enabled)
    }

    func setClipboardSaveFiles(_ enabled: Bool) {
        clipboardSaveFiles = enabled
        persist(ClipboardKeys.saveFiles, enabled)
    }

    func setClipboardSaveImages(_ enabled: Bool) {
        clipboardSaveImages = enabled
        persist(ClipboardKeys.saveImages, enabled)
    }

    func setClipboardSaveText(_ enabled: Bool) {
        clipboardSaveText = enabled
        persist(ClipboardKeys.saveText, enabled)
    }

    func setClipboardSortMode(_ mode: ClipboardSortMode) {
        clipboardSortMode = mode
        persist(ClipboardKeys.sortMode, mode.rawValue)
    }

    func setClipboardPopupPosition(_ position: ClipboardPopupPosition) {
        clipboardPopupPosition = position
        persist(ClipboardKeys.popupPosition, position.rawValue)
    }

    func setClipboardPinEdge(_ edge: ClipboardPinEdge) {
        clipboardPinEdge = edge
        persist(ClipboardKeys.pinEdge, edge.rawValue)
    }

    func setClipboardImageHeight(_ height: Double) {
        clipboardImageHeight = min(120, max(24, height))
        defaults.set(clipboardImageHeight, forKey: ClipboardKeys.imageHeight)
    }

    func setClipboardPreviewDelayMs(_ ms: Int) {
        clipboardPreviewDelayMs = min(2000, max(0, ms))
        defaults.set(clipboardPreviewDelayMs, forKey: ClipboardKeys.previewDelayMs)
    }

    func setClipboardShowSearchField(_ enabled: Bool) {
        clipboardShowSearchField = enabled
        persist(ClipboardKeys.showSearchField, enabled)
    }

    func setClipboardShowFooter(_ enabled: Bool) {
        clipboardShowFooter = enabled
        persist(ClipboardKeys.showFooter, enabled)
    }

    func setClipboardIgnoredApps(_ apps: [String]) {
        clipboardIgnoredApps = apps
        defaults.set(apps, forKey: ClipboardKeys.ignoredApps)
    }

    func addClipboardIgnoredApp(_ bundleID: String) {
        let id = bundleID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !id.isEmpty, !clipboardIgnoredApps.contains(id) else { return }
        setClipboardIgnoredApps(clipboardIgnoredApps + [id])
    }

    func removeClipboardIgnoredApp(_ bundleID: String) {
        setClipboardIgnoredApps(clipboardIgnoredApps.filter { $0 != bundleID })
    }

    func setClipboardIgnoreConcealed(_ enabled: Bool) {
        clipboardIgnoreConcealed = enabled
        persist(ClipboardKeys.ignoreConcealed, enabled)
    }

    func setClipboardCapturePaused(_ paused: Bool) {
        clipboardCapturePaused = paused
        persist(ClipboardKeys.capturePaused, paused)
    }

    func setClipboardClearOnQuit(_ enabled: Bool) {
        clipboardClearOnQuit = enabled
        persist(ClipboardKeys.clearOnQuit, enabled)
    }

    func setClipboardClearSystemClipboard(_ enabled: Bool) {
        clipboardClearSystemClipboard = enabled
        persist(ClipboardKeys.clearSystemClipboard, enabled)
    }
}
