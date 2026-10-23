import AppKit
import QuartzCore
import SwiftUI

/// Separate non-activating preview window so content is never clipped by the list panel.
///
/// Motion: slides out from the list edge with a fade on first show, swaps content in
/// place (80ms crossfade, no slide) while it stays up, and slides back toward the
/// list when it hides. Reduce Motion keeps only the fades.
@MainActor
final class ClipboardPreviewPanelController {
    static let shared = ClipboardPreviewPanelController()

    private var panel: ChromePanel?
    private var host: NSHostingView<ClipboardPreviewPopover>?
    /// Logical visibility. False as soon as a hide starts, even while it fades.
    private(set) var isShowing = false
    /// Which side of the list the preview sits on (decides slide direction).
    private var sitsRight = true
    private var hideGeneration: UInt64 = 0

    private static let restingAlpha: CGFloat = 0.96

    var window: NSWindow? { panel }
    var frame: NSRect? { isShowing ? panel?.frame : nil }
    var isKeyWindow: Bool { panel?.isKeyWindow == true }

    func show(item: ClipboardItem, image: NSImage?, beside listFrame: NSRect) {
        // Measure the free-height card off-window, then pin it to the capped height.
        // The hosting view inside the panel reports the size it already has
        // (sizingOptions are off), so measuring it kept every preview at its first
        // size and cropped the image and both horizontal borders. The pinned card
        // clips inside its own border, so long text cannot push the strokes out.
        let size = CGSize(
            width: ClipboardPreviewPopover.width,
            height: ClipboardPreviewLayout.cardHeight(
                measured: measure(ClipboardPreviewPopover(item: item, image: image))
            )
        )
        let root = ClipboardPreviewPopover(item: item, image: image, height: size.height)
        let wasShowing = isShowing && panel?.isVisible == true
        let midHide = !isShowing && panel?.isVisible == true
        if panel == nil {
            let panel = ChromePanel(radius: 0)
            panel.resignKeyOnMouseUp = false
            // Capturable in screenshots, like the list (ChromePanel defaults to hidden).
            panel.sharingType = .readOnly
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.animationBehavior = .none
            let host = NSHostingView(rootView: root)
            host.wantsLayer = true
            // We size the window ourselves (content + bevel gutter). Letting the hosting
            // view resize it fought the slide animation by 3pt per frame.
            host.sizingOptions = []
            panel.contentView = host
            self.panel = panel
            self.host = host
        } else {
            if wasShowing, let layer = host?.layer {
                // In-place swap: a short crossfade instead of a hard cut or a re-slide.
                let fade = CATransition()
                fade.type = .fade
                fade.duration = PanelMotion.previewSwap
                fade.timingFunction = PanelMotion.easeOut
                layer.add(fade, forKey: "swap")
            }
            host?.rootView = root
        }
        guard let panel, let host else { return }
        let chrome = CGSize(width: size.width + Ink.bevelOffset, height: size.height + Ink.bevelOffset)
        host.frame = NSRect(origin: .zero, size: chrome)
        let target = place(size: chrome, visual: size, beside: listFrame)
        isShowing = true
        hideGeneration &+= 1
        if wasShowing {
            // Content change only: land on the new size at once, top edge fixed.
            // Through the animator with zero duration, so a swap during the open
            // slide replaces the slide's target instead of being undone by it
            // (the window kept the first item's size around the new content).
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0
                panel.animator().setFrame(target, display: true)
                panel.animator().alphaValue = Self.restingAlpha
            }
            AnimSampler.mark("preview-swap", panel)
            return
        }
        panel.orderFrontRegardless()
        if midHide {
            PanelMotion.present(panel, to: target, alpha: Self.restingAlpha, from: .zero,
                                duration: PanelMotion.previewOpen, fromCurrent: true)
        } else {
            // Start tucked 12pt back toward the list, slide out to the side it sits on.
            let tuck = sitsRight ? -PanelMotion.previewTravel : PanelMotion.previewTravel
            PanelMotion.present(panel, to: target, alpha: Self.restingAlpha,
                                from: CGVector(dx: tuck, dy: 0), duration: PanelMotion.previewOpen)
        }
        AnimSampler.sample("preview-open", panel)
    }

    /// Slides back toward the list. `animated: false` when the list closes on a pick.
    func hide(animated: Bool = true) {
        guard let panel else { return }
        let wasShowing = isShowing
        isShowing = false
        guard panel.isVisible else { return }
        hideGeneration &+= 1
        let generation = hideGeneration
        if !animated {
            panel.orderOut(nil)
            panel.alphaValue = Self.restingAlpha
            return
        }
        guard wasShowing else { return }
        let tuck = sitsRight ? -PanelMotion.previewTravel : PanelMotion.previewTravel
        PanelMotion.dismiss(panel, toward: CGVector(dx: tuck, dy: 0), duration: PanelMotion.previewClose) { [weak self] in
            guard let self, self.hideGeneration == generation, !self.isShowing else { return }
            panel.orderOut(nil)
        }
        AnimSampler.sample("preview-close", panel)
    }

    private var measurer: NSHostingView<ClipboardPreviewPopover>?

    private func measure(_ root: ClipboardPreviewPopover) -> CGFloat {
        let measurer = self.measurer ?? NSHostingView(rootView: root)
        self.measurer = measurer
        measurer.rootView = root
        return measurer.fittingSize.height
    }

    private func place(size: CGSize, visual: CGSize, beside listFrame: NSRect) -> NSRect {
        let screen = ScreenGeometry.screen(containingAppKitPoint: NSPoint(x: listFrame.midX, y: listFrame.midY))
            ?? NSScreen.main
            ?? NSScreen.screens.first
        guard let screen else { return NSRect(origin: .zero, size: size) }
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
        sitsRight = origin.x >= listFrame.midX
        return NSRect(origin: origin, size: size)
    }
}
