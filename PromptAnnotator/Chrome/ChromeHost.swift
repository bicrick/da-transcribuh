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

    /// Fades the markup bar in and out. Holding a session key shows it, so it has to
    /// feel instant without popping: a short ease-out on alpha, nothing else moves.
    func setToolbarVisible(_ visible: Bool) {
        guard let session else { return }
        ensureHosts(session)
        guard let panel = toolbarPanel else { return }
        if visible {
            relayout()
            fadeToolbar(panel, to: 1)
        } else {
            fadeToolbar(panel, to: 0)
        }
    }

    func hideToolbar() {
        toolbarFadeToken += 1
        toolbarTarget = 0
        toolbarPanel?.orderOut(nil)
        toolbarPanel?.alphaValue = 1
    }

    private var toolbarFadeToken = 0
    private var toolbarTarget: CGFloat = 0
    static let toolbarFadeIn: TimeInterval = 0.14
    static let toolbarFadeOut: TimeInterval = 0.1

    private func fadeToolbar(_ panel: ChromePanel, to target: CGFloat) {
        let showing = target > 0
        if toolbarTarget == target, panel.isVisible == showing { return }
        toolbarTarget = target
        toolbarFadeToken += 1
        let token = toolbarFadeToken
        if showing, !panel.isVisible {
            panel.alphaValue = 0
            panel.orderFrontRegardless()
        }
        guard panel.isVisible else { return }
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else {
            panel.alphaValue = 1
            if !showing { panel.orderOut(nil) }
            return
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = showing ? Self.toolbarFadeIn : Self.toolbarFadeOut
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            context.allowsImplicitAnimation = true
            panel.animator().alphaValue = target
        } completionHandler: {
            DispatchQueue.main.async {
                guard self.toolbarFadeToken == token, !showing else { return }
                panel.orderOut(nil)
                panel.alphaValue = 1
            }
        }
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
        placeIsland(size, animated: false)
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
        // `size` is chrome (bar + double-pane gutter). Center on the bar face so the
        // down-right offset doesn’t shift the bar’s visual position.
        let bar = session?.islandBarSize() ?? CGSize(
            width: max(1, size.width - Ink.buttonShadow),
            height: max(1, size.height - Ink.buttonShadow)
        )
        place(
            panel,
            size: size,
            screen: ScreenGeometry.screenUnderMouse(),
            animated: animated,
            visualSize: bar
        )
    }

    func dismissIsland(animated: Bool, hideToolbar: Bool, completion: @escaping () -> Void) {
        fadeToken += 1
        let token = fadeToken
        if hideToolbar {
            self.hideToolbar()
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
            placeIsland(session.islandPanelSize(), animated: !session.islandChrome.isAnimating)
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

    private func place(
        _ panel: ChromePanel?,
        size: CGSize,
        screen: NSScreen?,
        animated: Bool,
        visualSize: CGSize? = nil
    ) {
        guard let panel, let screen, size.width > 1, size.height > 1 else { return }
        let visible = screen.visibleFrame
        // When `visualSize` is set (island bar face), anchor that rect — not the
        // shadow gutter — so the double-pane offset doesn’t nudge the bar.
        let anchor = visualSize ?? size
        let origin = NSPoint(
            x: visible.midX - anchor.width / 2,
            y: visible.maxY - anchor.height - 8
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
