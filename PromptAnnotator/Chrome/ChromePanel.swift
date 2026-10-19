import AppKit

final class ChromePanel: NSPanel {
    init(radius: CGFloat) {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 240, height: 44),
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.screenSaverWindow)))
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        hidesOnDeactivate = false
        isMovable = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        sharingType = .none
        isReleasedWhenClosed = false
        animationBehavior = .utilityWindow
        becomesKeyOnlyIfNeeded = true
        cornerRadius = radius
    }

    var cornerRadius: CGFloat = 16 {
        didSet { applyShape() }
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func setContentSize(_ size: NSSize) {
        super.setContentSize(size)
        applyShape()
    }

    func place(on screen: NSScreen, edge: VerticalEdge) {
        let size = frame.size
        let visible = screen.visibleFrame
        let x = visible.midX - size.width / 2
        let y: CGFloat
        switch edge {
        case .top:
            y = visible.maxY - size.height - 8
        case .bottom:
            y = visible.minY + 12
        }
        setFrameOrigin(NSPoint(x: x, y: y))
        applyShape()
    }

    func placeCentered(on screen: NSScreen) {
        let visible = screen.visibleFrame
        let size = frame.size
        let origin = NSPoint(
            x: visible.midX - size.width / 2,
            y: visible.midY - size.height / 2
        )
        setFrameOrigin(origin)
        applyShape()
    }

    override func sendEvent(_ event: NSEvent) {
        super.sendEvent(event)
        if event.type == .leftMouseUp {
            resignKey()
        }
    }

    private func applyShape() {
        guard let content = contentView else { return }
        content.wantsLayer = true
        content.layer?.cornerRadius = cornerRadius
        content.layer?.cornerCurve = .continuous
        content.layer?.masksToBounds = true
        content.layer?.backgroundColor = NSColor.clear.cgColor
        invalidateShadow()
    }
}

enum VerticalEdge {
    case top
    case bottom
}
