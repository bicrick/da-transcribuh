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
        // Soft system shadow off — island draws the Paint double-pane inside its frame.
        hasShadow = false
        sharingType = .none
        isReleasedWhenClosed = false
        animationBehavior = .utilityWindow
        becomesKeyOnlyIfNeeded = true
        cornerRadius = radius
    }

    var cornerRadius: CGFloat = 3 {
        didSet { applyShape() }
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func setContentSize(_ size: NSSize) {
        super.setContentSize(size)
        applyShape()
    }

    func adopt(frame: NSRect, animated: Bool) {
        guard frame.width > 1, frame.height > 1 else { return }
        let current = self.frame
        let moved = abs(current.width - frame.width) > 0.5
            || abs(current.height - frame.height) > 0.5
            || abs(current.origin.x - frame.origin.x) > 0.5
            || abs(current.origin.y - frame.origin.y) > 0.5
        guard moved else { return }
        let travel = hypot(current.midX - frame.midX, current.midY - frame.midY)
        let glides = animated && isVisible && travel < 140
        if glides {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.48
                context.timingFunction = CAMediaTimingFunction(controlPoints: 0.16, 0.84, 0.28, 1)
                animator().setFrame(frame, display: true)
            }
        } else {
            setFrame(frame, display: true)
        }
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
        // Do not clip — the Paint double-pane offset draws into the chrome gutter
        // (`Ink.bevelOffset`) reserved outside the bar face.
        content.layer?.masksToBounds = false
        content.layer?.backgroundColor = NSColor.clear.cgColor
        invalidateShadow()
    }
}

enum VerticalEdge {
    case top
    case bottom
}
