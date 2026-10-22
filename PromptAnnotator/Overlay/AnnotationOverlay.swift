import AppKit
import QuartzCore

final class AnnotationCanvasView: NSView {
    var shapes: [AnnotationShape] = []
    var draft: AnnotationShape?
    var textEdit: TextEdit?
    var caretOn = true
    private(set) var selection: CGRect?

    /// When true, the snip shade/border are CAShapeLayers (capture-drag hot path).
    /// When marks are present, selection falls back into `draw(_:)` so strokes stay above the shade.
    private var layerBackedSelection = true
    private let shadeLayer = CAShapeLayer()
    private let borderOuterLayer = CAShapeLayer()
    private let borderInnerLayer = CAShapeLayer()

    override var isOpaque: Bool { false }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        configureLayers()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configureLayers()
    }

    private func configureLayers() {
        wantsLayer = true
        layerContentsRedrawPolicy = .onSetNeedsDisplay

        shadeLayer.fillColor = NSColor.black.withAlphaComponent(0.22).cgColor
        shadeLayer.fillRule = .evenOdd
        shadeLayer.strokeColor = nil
        shadeLayer.isHidden = true

        borderOuterLayer.fillColor = nil
        borderOuterLayer.strokeColor = NSColor.black.cgColor
        borderOuterLayer.lineWidth = 1
        borderOuterLayer.isHidden = true

        borderInnerLayer.fillColor = nil
        borderInnerLayer.strokeColor = NSColor.white.cgColor
        borderInnerLayer.lineWidth = 1
        borderInnerLayer.isHidden = true

        guard let root = layer else { return }
        for sub in [shadeLayer, borderOuterLayer, borderInnerLayer] {
            sub.contentsScale = NSScreen.main?.backingScaleFactor ?? 2
            root.addSublayer(sub)
        }
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        let scale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
        shadeLayer.contentsScale = scale
        borderOuterLayer.contentsScale = scale
        borderInnerLayer.contentsScale = scale
    }

    override func layout() {
        super.layout()
        let bounds = self.bounds
        shadeLayer.frame = bounds
        borderOuterLayer.frame = bounds
        borderInnerLayer.frame = bounds
        if layerBackedSelection, let selection {
            applyLayerSelectionPath(selection)
        }
    }

    private var hasMarks: Bool {
        shapes.contains(where: { $0.isSignificant() })
            || (draft?.isSignificant() ?? false)
            || textEdit != nil
    }

    /// Selection-only: updates CAShapeLayers without `needsDisplay` when there are no marks.
    func setSelection(_ rect: CGRect?) {
        let box = rect?.standardized
        if box == selection { return }
        selection = box
        refreshSelectionPresentation(marksChanged: false)
    }

    func setMarks(
        shapes: [AnnotationShape],
        draft: AnnotationShape?,
        textEdit: TextEdit?,
        caretOn: Bool
    ) {
        let changed =
            !shapeListsEqual(self.shapes, shapes)
            || !optionalShapeEqual(self.draft, draft)
            || !optionalTextEqual(self.textEdit, textEdit)
            || self.caretOn != caretOn
        self.shapes = shapes
        self.draft = draft
        self.textEdit = textEdit
        self.caretOn = caretOn
        // Layer-backed selection only when there are no marks (capture-drag hot path).
        let shouldLayer = !hasMarks
        if shouldLayer != layerBackedSelection {
            layerBackedSelection = shouldLayer
            refreshSelectionPresentation(marksChanged: true)
        } else if changed {
            needsDisplay = true
        }
    }

    private func refreshSelectionPresentation(marksChanged: Bool) {
        let box = selection
        if layerBackedSelection {
            hideLayerSelection(box == nil)
            if let box, box.width >= 1, box.height >= 1 {
                applyLayerSelectionPath(box)
                shadeLayer.isHidden = false
                borderOuterLayer.isHidden = false
                borderInnerLayer.isHidden = false
            }
            if marksChanged {
                needsDisplay = true
            }
        } else {
            hideLayerSelection(true)
            needsDisplay = true
        }
    }

    private func hideLayerSelection(_ hidden: Bool) {
        if hidden {
            shadeLayer.isHidden = true
            borderOuterLayer.isHidden = true
            borderInnerLayer.isHidden = true
            shadeLayer.path = nil
            borderOuterLayer.path = nil
            borderInnerLayer.path = nil
        }
    }

    private func applyLayerSelectionPath(_ box: CGRect) {
        let flipped = CGRect(
            x: box.minX,
            y: bounds.height - box.maxY,
            width: box.width,
            height: box.height
        )
        let shade = CGMutablePath()
        shade.addRect(bounds)
        shade.addRect(flipped)
        shadeLayer.path = shade
        borderOuterLayer.path = CGPath(rect: flipped, transform: nil)
        borderInnerLayer.path = CGPath(rect: flipped.insetBy(dx: 1, dy: 1), transform: nil)
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        context.saveGState()
        // The view is y-up. Put the renderer in display space: origin top-left, y down.
        context.translateBy(x: 0, y: bounds.height)
        context.scaleBy(x: 1, y: -1)
        if !layerBackedSelection, let selection {
            drawSelectionShade(selection, in: context)
        }
        ShapeRenderer.draw(
            shapes: shapes,
            draft: draft,
            textEdit: textEdit,
            caretOn: caretOn,
            in: context
        )
        if !layerBackedSelection, let selection {
            drawSelectionBorder(selection, in: context)
        }
        context.restoreGState()
    }

    private func drawSelectionShade(_ rect: CGRect, in context: CGContext) {
        let box = rect.standardized
        guard box.width >= 1, box.height >= 1 else { return }
        let shade = CGMutablePath()
        shade.addRect(bounds)
        shade.addRect(box)
        context.addPath(shade)
        context.setFillColor(NSColor.black.withAlphaComponent(0.22).cgColor)
        context.fillPath(using: .evenOdd)
    }

    private func drawSelectionBorder(_ rect: CGRect, in context: CGContext) {
        let box = rect.standardized
        guard box.width >= 1, box.height >= 1 else { return }
        context.setLineWidth(1)
        context.setStrokeColor(NSColor.black.cgColor)
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
    /// Called after panels are rebuilt for a display change so the session can re-push marks.
    var onScreensChanged: (() -> Void)?

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
                ShareableContentCacheWatcher.invalidate()
                guard let self, self.isShowing else { return }
                self.rebuild(keepingContent: true)
                for panel in self.panels.values {
                    panel.orderFrontRegardless()
                }
                self.onScreensChanged?()
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
            canvas.setMarks(
                shapes: active ? shapes : [],
                draft: active ? draft : nil,
                textEdit: active ? textEdit : nil,
                caretOn: caretOn
            )
            canvas.setSelection(active ? selection : nil)
        }
    }

    /// Selection-only update used while dragging a snip (skips mark dirty checks).
    func updateSelection(_ selection: CGRect?, displayID: CGDirectDisplayID?) {
        for (id, canvas) in canvases {
            canvas.setSelection(displayID == id ? selection : nil)
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
                canvas.setMarks(shapes: [], draft: nil, textEdit: nil, caretOn: true)
                canvas.setSelection(nil)
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

private func shapeListsEqual(_ a: [AnnotationShape], _ b: [AnnotationShape]) -> Bool {
    guard a.count == b.count else { return false }
    for i in a.indices where a[i] != b[i] { return false }
    return true
}

private func optionalShapeEqual(_ a: AnnotationShape?, _ b: AnnotationShape?) -> Bool {
    switch (a, b) {
    case (nil, nil): return true
    case let (l?, r?): return l == r
    default: return false
    }
}

private func optionalTextEqual(_ a: TextEdit?, _ b: TextEdit?) -> Bool {
    switch (a, b) {
    case (nil, nil): return true
    case let (l?, r?): return l == r
    default: return false
    }
}
