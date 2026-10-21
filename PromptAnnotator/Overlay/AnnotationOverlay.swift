import AppKit

final class AnnotationCanvasView: NSView {
    var shapes: [AnnotationShape] = []
    var draft: AnnotationShape?
    var textEdit: TextEdit?
    var caretOn = true
    var selection: CGRect?

    override var isOpaque: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        context.saveGState()
        // The view is y-up. Put the renderer in display space: origin top-left, y down.
        context.translateBy(x: 0, y: bounds.height)
        context.scaleBy(x: 1, y: -1)
        if let selection {
            drawSelectionShade(selection, in: context)
        }
        ShapeRenderer.draw(
            shapes: shapes,
            draft: draft,
            textEdit: textEdit,
            caretOn: caretOn,
            in: context
        )
        if let selection {
            drawSelectionBorder(selection, in: context)
        }
        context.restoreGState()
    }

    /// Dims the display around the snippet. The hole stays clear so the page shows through.
    private func drawSelectionShade(_ rect: CGRect, in context: CGContext) {
        let box = rect.standardized
        guard box.width >= 1, box.height >= 1 else { return }
        let shade = CGMutablePath()
        shade.addRect(bounds)
        shade.addRect(box)
        context.addPath(shade)
        context.setFillColor(NSColor.black.withAlphaComponent(0.28).cgColor)
        context.fillPath(using: .evenOdd)
    }

    private func drawSelectionBorder(_ rect: CGRect, in context: CGContext) {
        let box = rect.standardized
        guard box.width >= 1, box.height >= 1 else { return }
        context.setLineWidth(1)
        context.setStrokeColor(NSColor.black.withAlphaComponent(0.85).cgColor)
        context.stroke(box)
        context.setStrokeColor(NSColor.white.cgColor)
        context.stroke(box.insetBy(dx: 1, dy: 1))
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

/// Clear full-display surfaces. The windows ignore the mouse. `ShiftPenMonitor`
/// captures a drag in capture mode, and captures the pointer while Shift is held
/// in annotate mode.
@MainActor
final class OverlayController {
    private var panels: [CGDirectDisplayID: OverlayPanel] = [:]
    private var canvases: [CGDirectDisplayID: AnnotationCanvasView] = [:]
    private var screenObserver: NSObjectProtocol?
    private var isShowing = false

    func show() {
        isShowing = true
        watchScreens()
        rebuild(keepingContent: true)
        for panel in panels.values {
            panel.orderFrontRegardless()
        }
    }

    func hide() {
        isShowing = false
        for panel in panels.values {
            panel.orderOut(nil)
        }
    }

    private func watchScreens() {
        guard screenObserver == nil else { return }
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.isShowing else { return }
                self.rebuild(keepingContent: true)
                for panel in self.panels.values {
                    panel.orderFrontRegardless()
                }
            }
        }
    }

    func update(
        shapes: [AnnotationShape],
        draft: AnnotationShape?,
        textEdit: TextEdit?,
        caretOn: Bool,
        selection: CGRect?,
        displayID: CGDirectDisplayID?
    ) {
        for (id, canvas) in canvases {
            let active = displayID == id
            canvas.shapes = active ? shapes : []
            canvas.draft = active ? draft : nil
            canvas.textEdit = active ? textEdit : nil
            canvas.selection = active ? selection : nil
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
                canvas.selection = nil
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
