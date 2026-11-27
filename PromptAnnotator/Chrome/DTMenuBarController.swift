import AppKit
import Combine
import SwiftUI

/// AppKit status item + borderless square `ChromePanel` hosting `DTMenuBarPanel`.
///
/// Replaces SwiftUI's `MenuBarExtra(.window)` so macOS 26/27 Liquid Glass never wraps
/// the retro MS Paint menu in a rounded-corner glass frame or clips its hard offset bevel.
@MainActor
final class DTMenuBarController: NSObject {
    static let shared = DTMenuBarController()

    private var statusItem: NSStatusItem?
    private var panel: ChromePanel?
    private var host: MenuSizingHostingView?
    private var cancellables: Set<AnyCancellable> = []

    private var globalMouseMonitor: Any?
    private var localMouseMonitor: Any?
    private var localKeyMonitor: Any?
    private var resignObserver: NSObjectProtocol?
    private var appSwitchObserver: NSObjectProtocol?
    private var lastAnchorTopY: CGFloat?
    private var lastHiddenAt: CFAbsoluteTime = 0

    var isVisible: Bool {
        panel?.isVisible == true
    }

    /// Exposed for unit tests to verify borderless zero-radius chrome.
    var attachedPanel: ChromePanel? { panel }

    /// Installs the menu-bar `NSStatusItem` and binds its icon to Stay Awake / session state.
    func install() {
        guard statusItem == nil else { return }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            button.target = self
            button.action = #selector(toggleFromStatusButton(_:))
            button.sendAction(on: [.leftMouseDown, .rightMouseDown])
            button.imagePosition = .imageOnly
        }
        statusItem = item
        bindState()
        updateStatusIcon()
    }

    func remove() {
        hide()
        cancellables.removeAll()
        if let item = statusItem {
            NSStatusBar.system.removeStatusItem(item)
            statusItem = nil
        }
    }

    @objc private func toggleFromStatusButton(_ sender: Any?) {
        if isVisible {
            hide()
        } else {
            // Avoid a double-toggle if resignKey closed the panel on the same click.
            guard CFAbsoluteTimeGetCurrent() - lastHiddenAt > 0.2 else { return }
            show()
        }
    }

    func show() {
        StayAwakeController.shared.refreshSystemState()
        let panel = ensurePanel()
        positionPanel(panel, forceReanchor: true)
        panel.orderFrontRegardless()
        panel.makeKey()
        statusItem?.button?.highlight(true)
        installDismissMonitors()
    }

    func hide() {
        let wasVisible = isVisible
        removeDismissMonitors()
        statusItem?.button?.highlight(false)
        panel?.orderOut(nil)
        if wasVisible {
            lastHiddenAt = CFAbsoluteTimeGetCurrent()
        }
    }

    // MARK: - Icon state

    private func bindState() {
        let stayAwake = StayAwakeController.shared
        let session = SessionController.shared

        Publishers.Merge3(
            stayAwake.$mode.map { _ in () },
            stayAwake.$externallyDisabled.map { _ in () },
            session.$phase.map { _ in () }
        )
        .receive(on: RunLoop.main)
        .sink { [weak self] in
            self?.updateStatusIcon()
        }
        .store(in: &cancellables)
    }

    private func updateStatusIcon() {
        guard let button = statusItem?.button else { return }
        let stayAwake = StayAwakeController.shared
        let session = SessionController.shared
        let state = stayAwake.indicatorState

        if let activeIcon = MenuBarStatusIcon.image(for: state) {
            button.image = activeIcon
        } else {
            let base = NSImage(named: "MenuBarIcon")
            base?.isTemplate = true
            button.image = base
        }

        let label: String
        switch state {
        case .inactive:
            label = session.menuAccessibilityLabel
        case .lidClosed:
            label = "\(session.menuAccessibilityLabel) — Stay awake (lid closed)"
        case .lidOpen:
            label = "\(session.menuAccessibilityLabel) — Stay awake (lid open)"
        }
        button.setAccessibilityLabel(label)
        button.toolTip = state == .inactive ? "da transcribuh" : label
    }

    // MARK: - Borderless square panel

    /// Builds the borderless zero-radius panel used by the menu bar dropdown.
    static func makePanel() -> ChromePanel {
        let panel = ChromePanel(radius: 0)
        panel.level = .popUpMenu
        panel.sharingType = .readOnly
        panel.resignKeyOnMouseUp = false
        panel.acceptsMouseMovedEvents = true
        panel.animationBehavior = .none
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        return panel
    }

    private func ensurePanel() -> ChromePanel {
        if let panel { return panel }
        let panel = Self.makePanel()

        let root = DTMenuBarPanel(
            session: SessionController.shared,
            settings: AppSettings.shared,
            stayAwake: StayAwakeController.shared,
            onDismiss: { [weak self] in
                self?.hide()
            }
        )
        .focusEffectDisabled()

        let host = MenuSizingHostingView(rootView: AnyView(root))
        host.onSizeChange = { [weak self] in
            self?.resizeKeepingTopAnchored()
        }
        panel.contentView = host

        self.panel = panel
        self.host = host
        return panel
    }

    private func positionPanel(_ panel: ChromePanel, forceReanchor: Bool) {
        guard let host else { return }
        host.layoutSubtreeIfNeeded()
        let size = host.fittingSize
        guard size.width > 1, size.height > 1 else { return }

        let anchor = statusButtonScreenRect()
        let screen = anchor.flatMap { rect in
            NSScreen.screens.first { $0.frame.intersects(rect) }
        } ?? NSScreen.main

        let visible = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let topY: CGFloat
        if forceReanchor || lastAnchorTopY == nil {
            if let anchor {
                topY = min(anchor.minY, visible.maxY) - 4
            } else {
                topY = visible.maxY - 4
            }
            lastAnchorTopY = topY
        } else {
            topY = lastAnchorTopY!
        }

        let desiredX = anchor?.minX ?? (visible.maxX - size.width - 12)
        let clampedX = min(max(desiredX, visible.minX + 4), visible.maxX - size.width - 4)
        let clampedY = max(topY - size.height, visible.minY + 4)

        let frame = NSRect(
            x: clampedX.rounded(),
            y: clampedY.rounded(),
            width: ceil(size.width),
            height: ceil(size.height)
        )
        panel.setFrame(frame, display: true)
    }

    private func resizeKeepingTopAnchored() {
        guard let panel, panel.isVisible else { return }
        positionPanel(panel, forceReanchor: false)
    }

    private func statusButtonScreenRect() -> NSRect? {
        guard let button = statusItem?.button, let buttonWindow = button.window else { return nil }
        let inWindow = button.convert(button.bounds, to: nil)
        return buttonWindow.convertToScreen(inWindow)
    }

    // MARK: - Dismissal monitors

    private func installDismissMonitors() {
        removeDismissMonitors()

        globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.hide()
            }
        }

        localMouseMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .leftMouseUp, .rightMouseUp]) { [weak self] event in
            guard let self, self.isVisible else { return event }
            if event.type == .leftMouseUp || event.type == .rightMouseUp {
                if let statusWin = self.statusItem?.button?.window, event.window === statusWin {
                    DispatchQueue.main.async { [weak self] in
                        guard let self, self.isVisible else { return }
                        self.statusItem?.button?.highlight(true)
                    }
                }
                return event
            }
            if event.window === self.panel {
                return event
            }
            // Let `toggleFromStatusButton` handle clicks on the status bar icon itself.
            if let statusWin = self.statusItem?.button?.window, event.window === statusWin {
                return event
            }
            self.hide()
            return event
        }

        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.isVisible else { return event }
            if event.keyCode == 53 { // Escape
                self.hide()
                return nil
            }
            return event
        }

        if let panel {
            resignObserver = NotificationCenter.default.addObserver(
                forName: NSWindow.didResignKeyNotification,
                object: panel,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.hide()
                }
            }
        }

        appSwitchObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            let isSelf = app?.processIdentifier == ProcessInfo.processInfo.processIdentifier
            if !isSelf {
                Task { @MainActor [weak self] in
                    self?.hide()
                }
            }
        }
    }

    private func removeDismissMonitors() {
        if let m = globalMouseMonitor {
            NSEvent.removeMonitor(m)
            globalMouseMonitor = nil
        }
        if let m = localMouseMonitor {
            NSEvent.removeMonitor(m)
            localMouseMonitor = nil
        }
        if let m = localKeyMonitor {
            NSEvent.removeMonitor(m)
            localKeyMonitor = nil
        }
        if let o = resignObserver {
            NotificationCenter.default.removeObserver(o)
            resignObserver = nil
        }
        if let o = appSwitchObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(o)
            appSwitchObserver = nil
        }
    }
}

/// NSHostingView subclass that notifies the controller when SwiftUI content height changes
/// (e.g., expanding/collapsing inline Stay Awake controls) so the panel stays pinned under the bar.
private final class MenuSizingHostingView: NSHostingView<AnyView> {
    var onSizeChange: (() -> Void)?
    private var lastReportedSize: NSSize = .zero

    override func layout() {
        super.layout()
        let current = fittingSize
        if abs(current.width - lastReportedSize.width) > 0.5
            || abs(current.height - lastReportedSize.height) > 0.5 {
            lastReportedSize = current
            DispatchQueue.main.async { [weak self] in
                self?.onSizeChange?()
            }
        }
    }
}
