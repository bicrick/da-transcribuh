import AppKit
import SwiftUI

/// Floating non-activating Paint-styled clipboard history panel near the mouse.
@MainActor
final class ClipboardHistoryPanelController {
    static let shared = ClipboardHistoryPanelController()

    private var panel: ChromePanel?
    private var host: NSHostingView<ClipboardHistoryView>?
    private let store = ClipboardHistoryStore.shared

    var isVisible: Bool {
        panel?.isVisible == true
    }

    func toggle() {
        if isVisible {
            hide()
        } else {
            show()
        }
    }

    func show() {
        let root = ClipboardHistoryView(
            store: store,
            onPick: { [weak self] item, paste in
                let wrote = ClipboardHistoryController.shared.pick(item, paste: paste)
                // Enter / paste closes; ⌥Enter copy-only keeps the panel open (Maccy).
                if paste, wrote {
                    self?.hide()
                }
            },
            onClose: { [weak self] in self?.hide() }
        )
        if panel == nil {
            let panel = ChromePanel(radius: Ink.cardRadius)
            panel.resignKeyOnMouseUp = false
            let host = NSHostingView(rootView: root)
            host.frame = NSRect(origin: .zero, size: ClipboardHistoryView.preferredSize)
            panel.contentView = host
            panel.acceptsMouseMovedEvents = true
            self.panel = panel
            self.host = host
        } else {
            host?.rootView = root
        }
        guard let panel else { return }
        let size = ClipboardHistoryView.preferredSize
        // Chrome size includes double-pane gutter.
        let chrome = CGSize(width: size.width + Ink.bevelOffset, height: size.height + Ink.bevelOffset)
        placeNearMouse(panel: panel, size: chrome, visual: size)
        panel.alphaValue = 1
        panel.orderFrontRegardless()
        // Focus search without activating the app.
        panel.makeFirstResponder(host)
    }

    func hide() {
        panel?.orderOut(nil)
    }

    private func placeNearMouse(panel: ChromePanel, size: CGSize, visual: CGSize) {
        let mouse = NSEvent.mouseLocation
        let screen = ScreenGeometry.screen(containingAppKitPoint: mouse)
            ?? NSScreen.main
            ?? NSScreen.screens.first
        guard let screen else { return }
        let visible = screen.visibleFrame
        var origin = NSPoint(
            x: mouse.x - visual.width / 2,
            y: mouse.y - visual.height - 12
        )
        origin.x = min(max(origin.x, visible.minX + 8), visible.maxX - size.width - 8)
        origin.y = min(max(origin.y, visible.minY + 8), visible.maxY - size.height - 8)
        panel.adopt(frame: NSRect(origin: origin, size: size), animated: false)
    }
}
