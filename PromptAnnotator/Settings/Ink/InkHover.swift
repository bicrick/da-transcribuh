import AppKit
import SwiftUI

// MARK: - Retro hover
//
// One hover look for every clickable thing: a light tint fades in over the
// face, beveled controls lift 1pt off their shadow, and the pointer turns into
// a hand. It eases in and out over `Ink.hoverDuration`.
//
// The lift is an `.offset`, so layout never moves, and the hover area stays on
// the resting frame, so a lifted face can't flicker in and out of hover.
// Reduce Motion (system or `-DTReduceMotion YES`) drops the lift and keeps the
// tint fade, since a color fade is not motion. No focus rings are drawn.

extension Ink {
    /// Hover wash over light faces: 5% ink in light mode, 7% white in Graphite.
    static let hoverTint = color(
        light: NSColor(white: 0, alpha: 0.05),
        dark: NSColor(white: 1, alpha: 0.07)
    )
    /// Hover wash over solid primary faces (black in light, near-white in dark).
    static let hoverTintOnPrimary = color(
        light: NSColor(white: 1, alpha: 0.16),
        dark: NSColor(white: 0, alpha: 0.10)
    )
    /// How far a beveled face rises toward the viewer on hover.
    static let hoverLift: CGFloat = 1
    /// Hover fade time. Fast enough to feel direct, long enough not to snap.
    static let hoverDuration: Double = 0.13
}

/// Lets a view inside a hover target restyle itself (a tab label brightening).
private struct RetroHoveredKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var retroHovered: Bool {
        get { self[RetroHoveredKey.self] }
        set { self[RetroHoveredKey.self] = newValue }
    }
}

/// Which way a beveled face rises on hover. It moves away from its bevel:
/// up for buttons whose bevel sits below, up-left for tiles and keycaps whose
/// bevel sits below and to the right.
enum RetroLift {
    case none
    case up
    case upLeft
}

@MainActor
enum RetroHover {
    /// Draws every hover target in its hovered state. Used by the offscreen
    /// render tests only; a static rather than the environment because nested
    /// hosting views (DTScrollView) start a fresh environment.
    static var forceAll = false

    /// Pointing-hand cursor shared by every hover target. Counted so a target
    /// nested in another (a footer action inside a tile) can't drop the hand
    /// while the pointer is still over the outer one.
    private static var handCount = 0

    static func cursorEntered() {
        handCount += 1
        if handCount == 1 { NSCursor.pointingHand.push() }
    }

    static func cursorExited() {
        guard handCount > 0 else { return }
        handCount -= 1
        if handCount == 0 { NSCursor.pop() }
    }
}

struct RetroHoverModifier<S: Shape>: ViewModifier {
    var shape: S
    var tint: Color?
    var lift: RetroLift
    var cursor: Bool
    var enabled: Bool

    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @State private var hovering = false
    @State private var handHeld = false

    private var active: Bool { enabled && isEnabled }
    private var on: Bool { active && (hovering || RetroHover.forceAll) }
    private var lifts: Bool { lift != .none && on && !systemReduceMotion && !PanelMotion.reduceMotion }

    func body(content: Content) -> some View {
        content
            .overlay {
                if let tint {
                    shape
                        .fill(tint)
                        .opacity(on ? 1 : 0)
                        .allowsHitTesting(false)
                }
            }
            .offset(x: lifts && lift == .upLeft ? -Ink.hoverLift : 0, y: lifts ? -Ink.hoverLift : 0)
            .environment(\.retroHovered, on)
            .contentShape(shape)
            .onHover { over in
                withAnimation(.easeOut(duration: Ink.hoverDuration)) {
                    hovering = over
                }
                syncHand(over && active && cursor)
            }
            .onChange(of: active) { _, now in
                if !now { syncHand(false) }
            }
            .onDisappear { syncHand(false) }
    }

    private func syncHand(_ want: Bool) {
        if want, !handHeld {
            handHeld = true
            RetroHover.cursorEntered()
        } else if !want, handHeld {
            handHeld = false
            RetroHover.cursorExited()
        }
    }
}

extension View {
    /// The shared hover for clickable things. `tint` nil keeps the face as is
    /// (cursor and lift only). `lift` is for faces with a hard bevel behind them;
    /// draw that bevel after this modifier so it stays put while the face rises.
    func retroHover<S: Shape>(
        in shape: S,
        tint: Color? = Ink.hoverTint,
        lift: RetroLift = .none,
        cursor: Bool = true,
        enabled: Bool = true
    ) -> some View {
        modifier(RetroHoverModifier(shape: shape, tint: tint, lift: lift, cursor: cursor, enabled: enabled))
    }

    /// Rectangle version, for rows, tabs and square Paint controls.
    func retroHover(
        tint: Color? = Ink.hoverTint,
        lift: RetroLift = .none,
        cursor: Bool = true,
        enabled: Bool = true
    ) -> some View {
        retroHover(in: Rectangle(), tint: tint, lift: lift, cursor: cursor, enabled: enabled)
    }

    /// Foreground that brightens while an enclosing `retroHover` target is hovered.
    func retroHoverForeground(_ normal: Color, hovered: Color) -> some View {
        modifier(RetroHoverForeground(normal: normal, hovered: hovered))
    }
}

private struct RetroHoverForeground: ViewModifier {
    var normal: Color
    var hovered: Color
    @Environment(\.retroHovered) private var isHovered

    func body(content: Content) -> some View {
        content.foregroundStyle(isHovered ? hovered : normal)
    }
}
