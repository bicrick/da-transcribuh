import AppKit
import SwiftUI

/// Floating non-activating Paint-styled clipboard history panel near the mouse.
@MainActor
final class ClipboardHistoryPanelController {
    static let shared = ClipboardHistoryPanelController()

    private var panel: ChromePanel?
    private var host: NSHostingView<ClipboardHistoryView>?
    private let store = ClipboardHistoryStore.shared
    private var outsideGlobalMonitor: Any?
    private var outsideLocalMonitor: Any?
    private var resignObserver: NSObjectProtocol?
    private var resignHideWork: DispatchWorkItem?
    /// Polls while the screenshot UI is up so the panel survives the shot.
    private var screenshotWatch: Timer?
    /// The app in front when the panel opened. A change means the user left.
    private var openerPID: pid_t?
    /// Bumped on each `show()` so a stale resign-hide cannot close a fresh panel.
    private var showGeneration: UInt64 = 0
    /// True while the close fade runs. The window is still on screen but logically gone.
    private(set) var isClosing = false
    /// Final frame of the open slide. The preview anchors here, not to the mid-animation frame.
    private var restingFrame: NSRect = .zero
    /// Owns the preview's lifetime. Every close ends it; stale shows are refused.
    private lazy var previewOwner = ClipboardPreviewOwner<ClipboardItem>(
        show: { [weak self] item in
            guard let self else { return }
            ClipboardPreviewPanelController.shared.show(
                item: item,
                image: ClipboardHistoryStore.shared.image(for: item),
                beside: self.listFrame
            )
        },
        hide: { animated in ClipboardPreviewPanelController.shared.hide(animated: animated) }
    )

    var isVisible: Bool {
        panel?.isVisible == true && !isClosing
    }

    var window: NSWindow? { panel }

    var listFrame: NSRect {
        restingFrame.width > 1 ? restingFrame : (panel?.frame ?? .zero)
    }

    func toggle() {
        if isVisible {
            hide(reason: .hotkeyToggle)
        } else {
            show()
        }
    }

    func show() {
        // Catch a copy from the watcher's quiet interval before listing rows.
        ClipboardHistoryController.shared.checkPasteboardNow()
        PerfProbe.begin("panel", "open")
        defer { PerfProbe.endAfterDisplay("panel") }
        resignHideWork?.cancel()
        resignHideWork = nil
        showGeneration &+= 1
        // A new preview session. Requests scheduled by an earlier open stay refused.
        let previewToken = previewOwner.listOpened()
        let root = ClipboardHistoryView(
            store: store,
            onPick: { [weak self] item, paste in
                let wrote = ClipboardHistoryController.shared.pick(item, paste: paste)
                // Enter / click closes (copy, plus ⌘V only with "Paste automatically" on);
                // ⌥Enter copy-only keeps the panel open. Instant, so a synthesized ⌘V
                // lands in the target app, not a fading panel.
                if paste, wrote {
                    self?.hide(animated: false, reason: .pick)
                }
            },
            onClose: { [weak self] in self?.hide(reason: .escape) },
            openGeneration: showGeneration,
            onOpenPreferences: { [weak self] in
                self?.hide(reason: .preferences)
                SettingsPresenter.shared.show(page: .clipboard)
            },
            onPreview: { [weak self] item in
                // The view's hover debounce can fire after a close. The token says
                // which open scheduled it; the owner drops it if that open is over.
                guard let self else { return }
                self.previewOwner.request(item, token: previewToken)
            }
        )
        if panel == nil {
            let panel = ChromePanel(radius: 0)
            panel.resignKeyOnMouseUp = false
            // ChromePanel hides itself from screen capture (the recording island must
            // stay out of its own tiles). The clipboard panel should show up in ⌘⇧3/4/5.
            panel.sharingType = .readOnly
            panel.isOpaque = false
            panel.backgroundColor = .clear
            let host = NSHostingView(rootView: root)
            host.frame = NSRect(origin: .zero, size: ClipboardHistoryView.preferredSize)
            panel.contentView = host
            panel.acceptsMouseMovedEvents = true
            // PanelMotion owns open/close; AppKit's utility-window effect would double it.
            panel.animationBehavior = .none
            self.panel = panel
            self.host = host
        } else {
            host?.rootView = root
        }
        guard let panel else { return }
        let size = ClipboardHistoryView.preferredSize
        let chrome = CGSize(width: size.width + Ink.bevelOffset, height: size.height + Ink.bevelOffset)
        let wasOnScreen = panel.isVisible
        let wasClosing = isClosing
        isClosing = false
        panel.ignoresMouseEvents = false
        if wasClosing {
            // Re-shown mid-fade: ease back from wherever the fade got to.
            PanelMotion.present(panel, to: restingFrame, alpha: Self.restingAlpha, from: .zero,
                                duration: PanelMotion.listOpen, fromCurrent: true)
        } else {
            place(panel: panel, size: chrome, visual: size)
            restingFrame = panel.frame
        }
        // Nonactivating panel can still be key so arrows/Enter work with search off.
        // Focus first, motion second: nothing waits on the animation.
        panel.orderFrontRegardless()
        panel.makeKey()
        // Every open starts at the top with the search field focused (Maccy). Typing
        // filters at once; the key monitor still takes arrows and Return from the
        // field. This used to make the hosting view first responder, which took
        // focus off the search field on every reopen.
        resetForOpen(panel: panel)
        if !wasOnScreen {
            // Fade in while dropping 6pt into place.
            PanelMotion.present(panel, to: restingFrame, alpha: Self.restingAlpha,
                                from: CGVector(dx: 0, dy: PanelMotion.listOpenDrop),
                                duration: PanelMotion.listOpen)
        } else if !wasClosing {
            panel.alphaValue = Self.restingAlpha
        }
        AnimSampler.sample("list-open", panel)
        openerPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
        installOutsideClickMonitor()
        installResignObserver()
    }

    private static let restingAlpha: CGFloat = 0.95

    /// The hosting view is reused across opens, so the list kept its old scroll
    /// offset and AppKit kept whatever responder had focus. Reset both now and
    /// again after SwiftUI applies the cleared search (the list relayouts async).
    private func resetForOpen(panel: NSPanel) {
        let generation = showGeneration
        let apply = { [weak self, weak panel] in
            guard let self, let panel, self.showGeneration == generation, !self.isClosing else { return }
            Self.scrollToTop(Self.firstScrollView(in: self.host))
            Self.focusSearchField(in: panel, root: self.host)
        }
        apply()
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                apply()
                DispatchQueue.main.async { MainActor.assumeIsolated { apply() } }
            }
        }
    }

    /// Scrolls to the first row whether or not the document view is flipped.
    static func scrollToTop(_ scroll: NSScrollView?) {
        guard let scroll, let doc = scroll.documentView else { return }
        let clip = scroll.contentView
        let top = doc.isFlipped ? 0 : max(doc.frame.height - clip.bounds.height, 0)
        guard clip.bounds.origin.y != top else { return }
        clip.setBoundsOrigin(NSPoint(x: clip.bounds.origin.x, y: top))
        scroll.reflectScrolledClipView(clip)
    }

    /// Makes the search field first responder (it then hosts the field editor).
    /// Falls back to the hosting view when search is hidden in Settings.
    static func focusSearchField(in window: NSWindow, root: NSView?) {
        if let field = firstEditableTextField(in: root) {
            if let editor = window.firstResponder as? NSTextView, editor.delegate === field { return }
            window.makeFirstResponder(field)
        } else if let root, window.firstResponder !== root {
            window.makeFirstResponder(root)
        }
    }

    static func firstEditableTextField(in view: NSView?) -> NSTextField? {
        guard let view else { return nil }
        if let field = view as? NSTextField, field.isEditable, !field.isHidden { return field }
        for sub in view.subviews {
            if let hit = firstEditableTextField(in: sub) { return hit }
        }
        return nil
    }

    static func firstScrollView(in view: NSView?) -> NSScrollView? {
        guard let view else { return nil }
        if let scroll = view as? NSScrollView { return scroll }
        for sub in view.subviews {
            if let hit = firstScrollView(in: sub) { return hit }
        }
        return nil
    }

    private var hideGeneration: UInt64 = 0

    /// The single close path for every dismissal. It always ends the preview first.
    /// `animated: false` is for picks: the panel must be gone before the paste.
    func hide(animated: Bool = true, reason: ClipboardListDismissal = .programmatic) {
        resignHideWork?.cancel()
        resignHideWork = nil
        stopScreenshotWatch()
        removeOutsideClickMonitor()
        removeResignObserver()
        previewOwner.listClosed(reason, animated: animated)
        guard let panel, panel.isVisible else { return }
        hideGeneration &+= 1
        let generation = hideGeneration
        if !animated {
            isClosing = false
            panel.orderOut(nil)
            panel.alphaValue = Self.restingAlpha
            return
        }
        guard !isClosing else { return }
        isClosing = true
        panel.ignoresMouseEvents = true
        // Fade out while lifting 4pt.
        PanelMotion.dismiss(panel, toward: CGVector(dx: 0, dy: PanelMotion.listCloseLift),
                            duration: PanelMotion.listClose) { [weak self] in
            guard let self, self.hideGeneration == generation, self.isClosing else { return }
            self.isClosing = false
            panel.orderOut(nil)
            panel.ignoresMouseEvents = false
        }
        AnimSampler.sample("list-close", panel)
    }

    private func installOutsideClickMonitor() {
        removeOutsideClickMonitor()
        // Global: other apps. Local: same-app clicks (preview / Settings) skipped by global.
        outsideGlobalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.dismissIfClickOutside()
            }
        }
        outsideLocalMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            MainActor.assumeIsolated {
                self?.dismissIfClickOutside()
            }
            return event
        }
    }

    private func dismissIfClickOutside() {
        guard isVisible, let panel else { return }
        let screenPoint = NSEvent.mouseLocation
        let listHit = panel.frame.contains(screenPoint)
        let previewHit = ClipboardPreviewPanelController.shared.frame?.contains(screenPoint) == true
        // A ⌘⇧4 crosshair drag or window pick lands on the screenshot overlay, not
        // on another app. Stay open for the shot.
        if !listHit && !previewHit && ScreenshotUI.covers(screenPoint) {
            startScreenshotWatch()
            return
        }
        if !listHit && !previewHit {
            hide(reason: .clickOutside)
        }
    }

    private func removeOutsideClickMonitor() {
        if let outsideGlobalMonitor {
            NSEvent.removeMonitor(outsideGlobalMonitor)
            self.outsideGlobalMonitor = nil
        }
        if let outsideLocalMonitor {
            NSEvent.removeMonitor(outsideLocalMonitor)
            self.outsideLocalMonitor = nil
        }
    }

    private func installResignObserver() {
        removeResignObserver()
        let generation = showGeneration
        resignObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification,
            object: panel,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.resignHideWork?.cancel()
                let work = DispatchWorkItem { [weak self] in
                    MainActor.assumeIsolated {
                        guard let self else { return }
                        guard self.isVisible, self.showGeneration == generation else { return }
                        if self.shouldKeepOpenAfterResign() { return }
                        // Focus went to the screenshot UI (⌘⇧4 or ⌘⇧5), not to another app.
                        if ScreenshotUI.isActive(), !self.userSwitchedApps() {
                            self.startScreenshotWatch()
                            return
                        }
                        self.hide(reason: self.userSwitchedApps() ? .appSwitch : .resignKey)
                    }
                }
                self.resignHideWork = work
                // Delay so a click that activates another app still closes us.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05, execute: work)
            }
        }
    }

    /// True when a different regular app came to the front since the panel opened.
    private func userSwitchedApps() -> Bool {
        let front = NSWorkspace.shared.frontmostApplication
        if ScreenshotUI.isFrontmost(front) { return false }
        guard let front, let openerPID else { return false }
        return front.processIdentifier != openerPID
            && front.processIdentifier != ProcessInfo.processInfo.processIdentifier
    }

    private func startScreenshotWatch() {
        guard screenshotWatch == nil else { return }
        let generation = showGeneration
        let timer = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                guard self.isVisible, self.showGeneration == generation else {
                    self.stopScreenshotWatch()
                    return
                }
                // The post-shot thumbnail can linger. Only the crosshair, toolbar
                // or the Screenshot app in front count as "still shooting".
                if ScreenshotUI.isFrontmost(NSWorkspace.shared.frontmostApplication)
                    || ScreenshotUI.windows().contains(where: Self.isFullScreenshotWindow) {
                    return
                }
                self.stopScreenshotWatch()
                if self.userSwitchedApps() {
                    self.hide(reason: .screenshotEnded)
                } else if self.panel?.isKeyWindow != true {
                    // Back from the shot: take keys again so Escape, arrows and typing work.
                    self.panel?.makeKey()
                }
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        screenshotWatch = timer
    }

    private func stopScreenshotWatch() {
        screenshotWatch?.invalidate()
        screenshotWatch = nil
    }

    /// The crosshair overlay spans a screen; the ⌘⇧5 toolbar sits above the Dock.
    /// Both are wider than the floating thumbnail (about 220pt).
    private static func isFullScreenshotWindow(_ info: [String: Any]) -> Bool {
        guard let dict = info[kCGWindowBounds as String] as? NSDictionary,
              let rect = CGRect(dictionaryRepresentation: dict as CFDictionary) else { return false }
        return rect.width > 300
    }

    /// Keep the list open when focus moves to our preview, or the pointer is still on chrome.
    private func shouldKeepOpenAfterResign() -> Bool {
        if panel?.isKeyWindow == true { return true }
        if ClipboardPreviewPanelController.shared.isKeyWindow { return true }
        let mouse = NSEvent.mouseLocation
        if panel?.frame.contains(mouse) == true { return true }
        if ClipboardPreviewPanelController.shared.frame?.contains(mouse) == true { return true }
        return false
    }

    private func removeResignObserver() {
        if let resignObserver {
            NotificationCenter.default.removeObserver(resignObserver)
            self.resignObserver = nil
        }
    }

    private func place(panel: ChromePanel, size: CGSize, visual: CGSize) {
        let settings = AppSettings.shared
        let screen = NSScreen.main ?? NSScreen.screens.first
        guard let screen else { return }
        let visible = screen.visibleFrame
        var origin: NSPoint
        switch settings.clipboardPopupPosition {
        case .cursor:
            let mouse = NSEvent.mouseLocation
            let mouseScreen = ScreenGeometry.screen(containingAppKitPoint: mouse) ?? screen
            let frame = ClipboardCursorPlacement.frame(mouse: mouse, size: size, visible: mouseScreen.visibleFrame)
            panel.adopt(frame: frame, animated: false)
            return
        case .menuBar:
            origin = NSPoint(
                x: visible.midX - visual.width / 2,
                y: visible.maxY - size.height - 24
            )
        case .screenCenter:
            origin = NSPoint(
                x: visible.midX - visual.width / 2,
                y: visible.midY - visual.height / 2
            )
        }
        origin.x = min(max(origin.x, visible.minX + 8), visible.maxX - size.width - 8)
        origin.y = min(max(origin.y, visible.minY + 8), visible.maxY - size.height - 8)
        panel.adopt(frame: NSRect(origin: origin, size: size), animated: false)
    }
}

/// "At cursor" placement, Maccy style. The list opens just beside the pointer, never
/// under it, so the click or hover that follows the hotkey can't land on a row.
/// AppKit screen coordinates (origin bottom-left, y up).
enum ClipboardCursorPlacement {
    /// Space between the pointer and the panel edge.
    static let gap: CGFloat = 6
    /// Space kept between the panel and the visible-frame edge.
    static let margin: CGFloat = 8

    /// Prefers right of and below the pointer (top-left corner at `gap` right, `gap` down).
    /// Flips left when the right side would run off screen, and up when below would.
    /// When neither side fits it clamps to the visible frame. The pointer stays outside
    /// whenever the panel fits beside it on either side.
    static func frame(
        mouse: CGPoint,
        size: CGSize,
        visible: CGRect,
        gap: CGFloat = gap,
        margin: CGFloat = margin
    ) -> CGRect {
        let minX = visible.minX + margin
        let maxX = visible.maxX - margin
        let minY = visible.minY + margin
        let maxY = visible.maxY - margin

        let right = mouse.x + gap
        let left = mouse.x - gap - size.width
        var x: CGFloat
        if right + size.width <= maxX {
            x = right
        } else if left >= minX {
            x = left
        } else {
            x = min(max(right, minX), maxX - size.width)
        }
        x = max(x, minX)

        let below = mouse.y - gap - size.height
        let above = mouse.y + gap
        var y: CGFloat
        if below >= minY {
            y = below
        } else if above + size.height <= maxY {
            y = above
        } else {
            y = min(max(below, minY), maxY - size.height)
        }
        y = max(y, minY)

        return CGRect(x: x, y: y, width: size.width, height: size.height)
    }
}
