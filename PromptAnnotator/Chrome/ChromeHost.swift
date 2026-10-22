import AppKit
import SwiftUI

@MainActor
final class ChromeHost {
    private var session: SessionController?
    private var islandPanel: ChromePanel?
    private var toolbarPanel: ChromePanel?
    private var islandHost: NSHostingView<RecordingIslandView>?
    private var toolbarHost: NSHostingView<MarkupToolbarView>?
    private var fadeToken = 0
    private var islandDismissing = false

    func attach(_ session: SessionController) {
        self.session = session
    }

    func setToolbarVisible(_ visible: Bool) {
        guard let session else { return }
        ensureHosts(session)
        if visible {
            toolbarPanel?.orderFrontRegardless()
        } else {
            toolbarPanel?.orderOut(nil)
        }
        relayout()
    }

    func hideToolbar() {
        toolbarPanel?.orderOut(nil)
    }

    /// Puts the pill on screen at alpha zero before its contents change, so the swap cannot flash.
    func beginIslandReveal() {
        guard let session else { return }
        ensureHosts(session)
        islandDismissing = false
        fadeToken += 1
        guard let panel = islandPanel else { return }
        panel.alphaValue = 0
        panel.orderFrontRegardless()
    }

    func revealIsland(size: CGSize, fadeIn: Bool) {
        guard let session else { return }
        ensureHosts(session)
        islandDismissing = false
        guard let panel = islandPanel else { return }
        if !fadeIn {
            fadeToken += 1
            panel.alphaValue = 1
        }
        panel.orderFrontRegardless()
        place(panel, size: size, screen: ScreenGeometry.screenUnderMouse(), animated: false)
        guard fadeIn else { return }
        let token = fadeToken
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.26
            context.timingFunction = CAMediaTimingFunction(controlPoints: 0.4, 0, 0.2, 1)
            panel.animator().alphaValue = 1
        } completionHandler: {
            DispatchQueue.main.async {
                guard self.fadeToken == token else { return }
                panel.alphaValue = 1
            }
        }
    }

    func placeIsland(_ size: CGSize, animated: Bool) {
        guard !islandDismissing, let panel = islandPanel else { return }
        place(panel, size: size, screen: ScreenGeometry.screenUnderMouse(), animated: animated)
    }

    func dismissIsland(animated: Bool, hideToolbar: Bool, completion: @escaping () -> Void) {
        fadeToken += 1
        let token = fadeToken
        if hideToolbar {
            toolbarPanel?.orderOut(nil)
        }
        guard let panel = islandPanel else {
            completion()
            return
        }
        let visible = panel.isVisible && panel.alphaValue > 0.01
        guard animated, visible else {
            panel.orderOut(nil)
            panel.alphaValue = 1
            islandDismissing = false
            completion()
            return
        }
        islandDismissing = true
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.34
            context.timingFunction = CAMediaTimingFunction(controlPoints: 0.4, 0, 0.2, 1)
            panel.animator().alphaValue = 0
        } completionHandler: {
            DispatchQueue.main.async {
                guard self.fadeToken == token else { return }
                panel.orderOut(nil)
                panel.alphaValue = 1
                self.islandDismissing = false
                completion()
            }
        }
    }

    func relayout() {
        guard let screen = ScreenGeometry.screenUnderMouse() else { return }
        if !islandDismissing, let session, session.islandChrome.presence != .hidden {
            place(
                islandPanel,
                size: session.islandPanelSize(),
                screen: screen,
                animated: !session.islandChrome.isAnimating
            )
        }
        resize(toolbarHost, panel: toolbarPanel, screen: screen, edge: .bottom, animated: false)
    }

    func hitRects() -> [CGRect] {
        [islandPanel, toolbarPanel].compactMap { panel in
            guard let panel, panel.isVisible else { return nil }
            return panel.frame
        }
    }

    func windowIDs() -> [CGWindowID] {
        [islandPanel, toolbarPanel].compactMap { panel in
            guard let panel, panel.isVisible, panel.windowNumber > 0 else { return nil }
            return CGWindowID(panel.windowNumber)
        }
    }

    private func ensureHosts(_ session: SessionController) {
        if islandPanel == nil {
            let panel = ChromePanel(radius: Ink.cardRadius)
            let host = NSHostingView(rootView: RecordingIslandView(session: session))
            host.sizingOptions = [.intrinsicContentSize]
            host.autoresizingMask = [.width, .height]
            panel.contentView = host
            islandPanel = panel
            islandHost = host
        }
        if toolbarPanel == nil {
            let panel = ChromePanel(radius: Ink.cardRadius)
            let host = NSHostingView(rootView: MarkupToolbarView(session: session))
            host.sizingOptions = [.intrinsicContentSize]
            panel.contentView = host
            toolbarPanel = panel
            toolbarHost = host
        }
    }

    private func place(_ panel: ChromePanel?, size: CGSize, screen: NSScreen?, animated: Bool) {
        guard let panel, let screen, size.width > 1, size.height > 1 else { return }
        let visible = screen.visibleFrame
        let origin = NSPoint(
            x: visible.midX - size.width / 2,
            y: visible.maxY - size.height - 8
        )
        panel.adopt(frame: NSRect(origin: origin, size: size), animated: animated)
    }

    private func resize<Content: View>(
        _ host: NSHostingView<Content>?,
        panel: ChromePanel?,
        screen: NSScreen,
        edge: VerticalEdge,
        animated: Bool
    ) {
        guard let host, let panel else { return }
        host.layoutSubtreeIfNeeded()
        var size = host.fittingSize
        if size.width < 40 || size.height < 20 {
            size = host.intrinsicContentSize
        }
        guard size.width > 1, size.height > 1 else { return }
        let visible = screen.visibleFrame
        let origin = NSPoint(
            x: visible.midX - size.width / 2,
            y: edge == .top ? visible.maxY - size.height - 8 : visible.minY + 12
        )
        panel.adopt(frame: NSRect(origin: origin, size: size), animated: animated)
    }
}
