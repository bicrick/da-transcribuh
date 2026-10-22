import AppKit
import SwiftUI

/// Separate non-activating preview window so content is never clipped by the list panel.
@MainActor
final class ClipboardPreviewPanelController {
    static let shared = ClipboardPreviewPanelController()

    private var panel: ChromePanel?
    private var host: NSHostingView<ClipboardPreviewPopover>?

    var frame: NSRect? { panel?.frame }

    func show(item: ClipboardItem, image: NSImage?, beside listFrame: NSRect) {
        let root = ClipboardPreviewPopover(item: item, image: image)
        if panel == nil {
            let panel = ChromePanel(radius: 0)
            panel.resignKeyOnMouseUp = false
            panel.isOpaque = false
            panel.backgroundColor = .clear
            let host = NSHostingView(rootView: root)
            panel.contentView = host
            self.panel = panel
            self.host = host
        } else {
            host?.rootView = root
        }
        guard let panel, let host else { return }
        let fitting = host.fittingSize
        let size = CGSize(
            width: max(280, min(fitting.width, 420)),
            height: max(160, min(fitting.height, 520))
        )
        host.frame = NSRect(origin: .zero, size: size)
        let chrome = CGSize(width: size.width + Ink.bevelOffset, height: size.height + Ink.bevelOffset)
        place(panel: panel, size: chrome, visual: size, beside: listFrame)
        panel.alphaValue = 0.96
        panel.orderFrontRegardless()
    }

    func hide() {
        panel?.orderOut(nil)
    }

    private func place(panel: ChromePanel, size: CGSize, visual: CGSize, beside listFrame: NSRect) {
        let screen = ScreenGeometry.screen(containingAppKitPoint: NSPoint(x: listFrame.midX, y: listFrame.midY))
            ?? NSScreen.main
            ?? NSScreen.screens.first
        guard let screen else { return }
        let visible = screen.visibleFrame
        let gutter: CGFloat = 8
        let preferRight = listFrame.midX < visible.midX
        var origin = NSPoint(
            x: preferRight ? listFrame.maxX + gutter : listFrame.minX - size.width - gutter,
            y: listFrame.maxY - visual.height
        )
        if origin.x < visible.minX + 8 {
            origin.x = listFrame.maxX + gutter
        }
        if origin.x + size.width > visible.maxX - 8 {
            origin.x = listFrame.minX - size.width - gutter
        }
        origin.x = min(max(origin.x, visible.minX + 8), visible.maxX - size.width - 8)
        origin.y = min(max(origin.y, visible.minY + 8), visible.maxY - size.height - 8)
        panel.adopt(frame: NSRect(origin: origin, size: size), animated: false)
    }
}
