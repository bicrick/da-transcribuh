import AppKit

final class AnnotationCanvasView: NSView {
    var shapes: [AnnotationShape] = []
    var draft: AnnotationShape?
    var textEdit: TextEdit?
    var caretOn = true

    override var isOpaque: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        context.saveGState()
        // The view is y-up. Put the renderer in display space: origin top-left, y down.
        context.translateBy(x: 0, y: bounds.height)
        context.scaleBy(x: 1, y: -1)
        ShapeRenderer.draw(
            shapes: shapes,
            draft: draft,
            textEdit: textEdit,
            caretOn: caretOn,
            in: context
        )
        context.restoreGState()
    }
}

final class OverlayPanel: NSPanel {
    init(frame: NSRect) {
        super.init(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.screenSaverWindow)) - 1)
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        isFloatingPanel = true
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = true
        hidesOnDeactivate = false
        sharingType = .none
        isReleasedWhenClosed = false
        animationBehavior = .none
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// Clear full-display surfaces. The windows ignore the mouse; `ShiftPenMonitor`
/// captures the pointer while Shift is held.
@MainActor
final class OverlayController {
    private var panels: [CGDirectDisplayID: OverlayPanel] = [:]
    private var canvases: [CGDirectDisplayID: AnnotationCanvasView] = [:]

    func show() {
        rebuild(keepingContent: true)
        for panel in panels.values {
            panel.orderFrontRegardless()
        }
    }

    func hide() {
        for panel in panels.values {
            panel.orderOut(nil)
        }
    }

    func update(
        shapes: [AnnotationShape],
        draft: AnnotationShape?,
        textEdit: TextEdit?,
        caretOn: Bool,
        displayID: CGDirectDisplayID?
    ) {
        for (id, canvas) in canvases {
            let active = displayID == id
            canvas.shapes = active ? shapes : []
            canvas.draft = active ? draft : nil
            canvas.textEdit = active ? textEdit : nil
            canvas.caretOn = caretOn
            canvas.needsDisplay = true
        }
    }

    func windowIDs() -> [CGWindowID] {
        panels.values.compactMap { panel in
            guard panel.isVisible, panel.windowNumber > 0 else { return nil }
            return CGWindowID(panel.windowNumber)
        }
    }

    private func rebuild(keepingContent: Bool) {
        let existing = canvases
        var nextPanels: [CGDirectDisplayID: OverlayPanel] = [:]
        var nextCanvases: [CGDirectDisplayID: AnnotationCanvasView] = [:]

        for screen in NSScreen.screens {
            guard let id = ScreenGeometry.displayID(of: screen) else { continue }
            let panel = panels[id] ?? OverlayPanel(frame: screen.frame)
            panel.setFrame(screen.frame, display: true)
            let canvas = existing[id] ?? AnnotationCanvasView(frame: panel.contentView?.bounds ?? screen.frame)
            canvas.frame = panel.contentView?.bounds ?? .zero
            canvas.autoresizingMask = [.width, .height]
            if panel.contentView !== canvas {
                panel.contentView = canvas
            }
            if !keepingContent {
                canvas.shapes = []
                canvas.draft = nil
                canvas.textEdit = nil
            }
            nextPanels[id] = panel
            nextCanvases[id] = canvas
        }

        for (id, panel) in panels where nextPanels[id] == nil {
            panel.orderOut(nil)
        }
        panels = nextPanels
        canvases = nextCanvases
    }
}
