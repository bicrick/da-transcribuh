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
        resize(islandHost, panel: islandPanel)
        resize(toolbarHost, panel: toolbarPanel)
        islandPanel?.place(on: screen, edge: .top)
        toolbarPanel?.place(on: screen, edge: .bottom)
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

    private func resize<Content: View>(_ host: NSHostingView<Content>?, panel: ChromePanel?) {
        guard let host, let panel else { return }
        var size = host.fittingSize
        if size.width < 40 || size.height < 20 {
            size = host.intrinsicContentSize
        }
        guard size.width > 1, size.height > 1 else { return }
        if abs(panel.frame.width - size.width) > 0.5 || abs(panel.frame.height - size.height) > 0.5 {
            panel.setContentSize(size)
        }
    }
}
