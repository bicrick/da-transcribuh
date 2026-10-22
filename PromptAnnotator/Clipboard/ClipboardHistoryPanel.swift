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
    /// Bumped on each `show()` so a stale resign-hide cannot close a fresh panel.
    private var showGeneration: UInt64 = 0
    /// True while the close fade runs. The window is still on screen but logically gone.
    private(set) var isClosing = false
    /// Final frame of the open slide. The preview anchors here, not to the mid-animation frame.
    private var restingFrame: NSRect = .zero

    var isVisible: Bool {
        panel?.isVisible == true && !isClosing
    }

    var window: NSWindow? { panel }

    var listFrame: NSRect {
        restingFrame.width > 1 ? restingFrame : (panel?.frame ?? .zero)
    }

    func toggle() {
        if isVisible {
            hide()
        } else {
            show()
        }
    }

    func show() {
        PerfProbe.begin("panel", "open")
        defer { PerfProbe.endAfterDisplay("panel") }
        resignHideWork?.cancel()
        resignHideWork = nil
        showGeneration &+= 1
        let root = ClipboardHistoryView(
            store: store,
            onPick: { [weak self] item, paste in
                let wrote = ClipboardHistoryController.shared.pick(item, paste: paste)
                // Enter / click paste closes; ⌥Enter copy-only keeps the panel open.
                // Instant: the synthesized ⌘V must land in the target app, not a fading panel.
                if paste, wrote {
                    self?.hide(animated: false)
                }
            },
            onClose: { [weak self] in self?.hide() },
            onOpenPreferences: { [weak self] in
                self?.hide()
                SettingsPresenter.shared.show(page: .clipboard)
            },
            onPreview: { item in
                if let item {
                    ClipboardPreviewPanelController.shared.show(
                        item: item,
                        image: ClipboardHistoryStore.shared.image(for: item),
                        beside: ClipboardHistoryPanelController.shared.listFrame
                    )
                } else {
                    ClipboardPreviewPanelController.shared.hide()
                }
            }
        )
        if panel == nil {
            let panel = ChromePanel(radius: 0)
            panel.resignKeyOnMouseUp = false
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
        panel.makeFirstResponder(host)
        if !wasOnScreen {
            // Fade in while dropping 6pt into place.
            PanelMotion.present(panel, to: restingFrame, alpha: Self.restingAlpha,
                                from: CGVector(dx: 0, dy: PanelMotion.listOpenDrop),
                                duration: PanelMotion.listOpen)
        } else if !wasClosing {
            panel.alphaValue = Self.restingAlpha
        }
        AnimSampler.sample("list-open", panel)
        installOutsideClickMonitor()
        installResignObserver()
    }

    private static let restingAlpha: CGFloat = 0.95
    private var hideGeneration: UInt64 = 0

    /// `animated: false` is for picks: the panel must be gone before the paste.
    func hide(animated: Bool = true) {
        resignHideWork?.cancel()
        resignHideWork = nil
        removeOutsideClickMonitor()
        removeResignObserver()
        ClipboardPreviewPanelController.shared.hide(animated: animated)
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
        if !listHit && !previewHit {
            hide()
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
                        self.hide()
                    }
                }
                self.resignHideWork = work
                // Delay so a click that activates another app still closes us.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05, execute: work)
            }
        }
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
            let vis = mouseScreen.visibleFrame
            origin = NSPoint(x: mouse.x - visual.width / 2, y: mouse.y - visual.height - 12)
            origin.x = min(max(origin.x, vis.minX + 8), vis.maxX - size.width - 8)
            origin.y = min(max(origin.y, vis.minY + 8), vis.maxY - size.height - 8)
            panel.adopt(frame: NSRect(origin: origin, size: size), animated: false)
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
