import Foundation

/// Every way the clipboard list can close. All of them go through one close path,
/// `ClipboardHistoryPanelController.hide(animated:reason:)`, which ends the preview.
enum ClipboardListDismissal: String, CaseIterable {
    case escape
    case clickOutside
    case resignKey
    case appSwitch
    case screenshotEnded
    case pick
    case hotkeyToggle
    case preferences
    case featureOff
    case programmatic
}

/// The preview's lifetime belongs to the list panel.
///
/// Each list open starts a session and hands out its token. Preview requests carry
/// the token of the open that scheduled them. A close ends the session at once, hides
/// the preview and makes every pending request stale, so a hover debounce or a
/// delayed show that fires after the list closed cannot bring the preview back.
@MainActor
final class ClipboardPreviewOwner<Item> {
    private(set) var isListOpen = false
    private(set) var session: UInt64 = 0

    private let showPreview: (Item) -> Void
    private let hidePreview: (_ animated: Bool) -> Void

    init(show: @escaping (Item) -> Void, hide: @escaping (_ animated: Bool) -> Void) {
        showPreview = show
        hidePreview = hide
    }

    /// Starts a new session. Requests from earlier opens stay stale.
    @discardableResult
    func listOpened() -> UInt64 {
        session &+= 1
        isListOpen = true
        return session
    }

    /// The single close path. Always hides the preview, even when it looks hidden,
    /// so a half-finished slide cannot be left behind.
    func listClosed(_ reason: ClipboardListDismissal, animated: Bool) {
        session &+= 1
        isListOpen = false
        hidePreview(animated)
    }

    /// True while `token` belongs to the open list.
    func allows(_ token: UInt64) -> Bool {
        isListOpen && token == session
    }

    /// Show `item`, or hide on nil. A stale token is refused outright.
    func request(_ item: Item?, token: UInt64) {
        guard let item else {
            hidePreview(true)
            return
        }
        guard allows(token) else { return }
        showPreview(item)
    }
}
