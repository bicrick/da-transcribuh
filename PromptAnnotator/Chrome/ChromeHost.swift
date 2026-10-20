import AppKit
import SwiftUI

@MainActor
final class ChromeHost {
    private var session: SessionController?
    private var islandPanel: ChromePanel?
    private var toolbarPanel: ChromePanel?
    private var islandHost: NSHostingView<RecordingIslandView>?
    private var toolbarHost: NSHostingView<MarkupToolbarView>?

    func attach(_ session: SessionController) {
        self.session = session
    }

    func showSession() {
        guard let session else { return }
        ensureHosts(session)
        if AppSettings.shared.islandStyle == .hidden {
            islandPanel?.orderOut(nil)
        } else {
            islandPanel?.orderFrontRegardless()
        }
        if session.showsToolbar {
            toolbarPanel?.orderFrontRegardless()
        } else {
            toolbarPanel?.orderOut(nil)
        }
        relayout()
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

    func showStatus() {
        guard let session else { return }
        ensureHosts(session)
        toolbarPanel?.orderOut(nil)
        islandPanel?.orderFrontRegardless()
        relayout()
    }

    func hideAll() {
        islandPanel?.orderOut(nil)
        toolbarPanel?.orderOut(nil)
    }

    func relayout() {
        guard let screen = ScreenGeometry.screenUnderMouse() else { return }
        resize(islandHost, panel: islandPanel, screen: screen, edge: .top, animated: true)
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
            let panel = ChromePanel(radius: 18)
            let host = NSHostingView(rootView: RecordingIslandView(session: session))
            host.sizingOptions = [.intrinsicContentSize]
            host.autoresizingMask = [.width, .height]
            panel.contentView = host
            islandPanel = panel
            islandHost = host
        }
        if toolbarPanel == nil {
            let panel = ChromePanel(radius: 22)
            let host = NSHostingView(rootView: MarkupToolbarView(session: session))
            host.sizingOptions = [.intrinsicContentSize]
            panel.contentView = host
            toolbarPanel = panel
            toolbarHost = host
        }
    }

    private func resize<Content: View>(
        _ host: NSHostingView<Content>?,
        panel: ChromePanel?,
        screen: NSScreen,
        edge: VerticalEdge,
        animated: Bool
    ) {
        guard let host, let panel else { return }
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
