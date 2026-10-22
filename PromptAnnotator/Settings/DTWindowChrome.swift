import AppKit
import SwiftUI

// MARK: - Title strip (custom traffic lights + wordmark + dither grip)

/// Settings title strip: outlined traffic lights, centered wordmark, dithered drag grip.
/// System buttons stay hidden; ⌘W / ⌘M still work via the window style mask.
struct DTTitleStrip: View {
    var body: some View {
        ZStack {
            HStack(spacing: 0) {
                DTTrafficLights()
                    .padding(.leading, Ink.space3)
                    .zIndex(2)
                Spacer(minLength: 0)
            }

            DTWordmark(size: 13)
                .allowsHitTesting(false)
        }
        .frame(height: Ink.titleStripHeight)
        .frame(maxWidth: .infinity)
        // Drag sits behind SwiftUI controls so traffic lights keep their hits.
        .background {
            WindowDragRegion()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Ink.window)
        .overlay(alignment: .bottom) {
            // Full-bleed 1pt rule — pixel-centered so corners don’t fray at 1×/2×.
            Rectangle()
                .fill(Ink.label)
                .frame(height: 1)
                .frame(maxWidth: .infinity)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("da transcribuh window")
    }
}

// MARK: - Traffic lights

enum DTWindowButtonKind {
    case close
    case miniaturize
    case zoom

    var glyph: String {
        switch self {
        case .close: return "×"
        case .miniaturize: return "−"
        case .zoom: return "+"
        }
    }

    var accessibilityLabel: String {
        switch self {
        case .close: return "Close"
        case .miniaturize: return "Minimize"
        case .zoom: return "Zoom"
        }
    }

    var paintFill: Color {
        switch self {
        case .close: return Ink.paintRed
        case .miniaturize: return Ink.paintYellow
        case .zoom: return Ink.paintGreen
        }
    }

    /// Direct window ops — avoid `performClose` / `performMiniaturize`, which no-op when
    /// the stock buttons are hidden (fullSizeContentView + custom strip).
    func perform(on window: NSWindow) {
        switch self {
        case .close:
            // Menu-bar companion: hide without quitting. Matches ⌘W / red light expectation.
            if window.isMiniaturized {
                window.deminiaturize(nil)
            }
            window.orderOut(nil)
        case .miniaturize:
            window.miniaturize(nil)
        case .zoom:
            window.zoom(nil)
        }
    }
}

struct DTTrafficLights: View {
    @State private var windowIsKey = true
    /// Group hover — all three glyphs appear together, like stock macOS lights.
    @State private var groupHovering = false

    var body: some View {
        HStack(spacing: Ink.space2) {
            DTTrafficLight(kind: .close, isKey: windowIsKey, showGlyph: groupHovering)
            DTTrafficLight(kind: .miniaturize, isKey: windowIsKey, showGlyph: groupHovering)
            DTTrafficLight(kind: .zoom, isKey: windowIsKey, showGlyph: groupHovering)
        }
        .padding(4)
        .contentShape(Rectangle())
        .onHover { groupHovering = $0 }
        .accessibilityElement(children: .contain)
        .onAppear { refreshKey(for: SettingsPresenter.shared.attachedWindow) }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { note in
            if let window = note.object as? NSWindow, isOurWindow(window) {
                windowIsKey = true
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didResignKeyNotification)) { note in
            if let window = note.object as? NSWindow, isOurWindow(window) {
                windowIsKey = false
            }
        }
    }

    private func isOurWindow(_ window: NSWindow) -> Bool {
        window === SettingsPresenter.shared.attachedWindow
            || window === OnboardingPresenter.shared.attachedWindow
    }

    private func refreshKey(for window: NSWindow?) {
        windowIsKey = window?.isKeyWindow ?? (SettingsPresenter.shared.attachedWindow?.isKeyWindow ?? true)
    }
}

private struct DTTrafficLight: View {
    let kind: DTWindowButtonKind
    var isKey: Bool
    var showGlyph: Bool

    private let diameter: CGFloat = 12

    var body: some View {
        Button {
            guard let window = resolvedWindow() else { return }
            kind.perform(on: window)
        } label: {
            ZStack {
                Circle()
                    .fill(isKey ? kind.paintFill : Ink.window)
                Circle()
                    .strokeBorder(Ink.label, lineWidth: 1)
                if showGlyph {
                    Text(kind.glyph)
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(Ink.label)
                        .offset(y: kind == .close ? -0.5 : 0)
                }
            }
            .frame(width: diameter, height: diameter)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(kind.accessibilityLabel)
        .accessibilityLabel(kind.accessibilityLabel)
    }

    private func resolvedWindow() -> NSWindow? {
        SettingsPresenter.shared.attachedWindow
            ?? OnboardingPresenter.shared.attachedWindow
            ?? NSApp.keyWindow
    }
}

// MARK: - Dither grip

struct DTDitherGrip: View {
    var body: some View {
        Canvas { context, size in
            let step: CGFloat = 2
            var y: CGFloat = 0
            while y < size.height {
                var x: CGFloat = 0
                while x < size.width {
                    let on = (Int(x / step) + Int(y / step)) % 2 == 0
                    if on {
                        let rect = CGRect(x: x, y: y, width: step, height: step)
                        context.fill(Path(rect), with: .color(Ink.label.opacity(0.55)))
                    }
                    x += step
                }
                y += step
            }
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Drag region (title-strip dragging)

/// Transparent NSView whose mouse-downs move the window — classic custom-titlebar drag.
/// `hitTest` returns nil so SwiftUI controls above (traffic lights) always win; the
/// window still drags via `mouseDownCanMoveWindow` when the event lands on empty chrome.
struct WindowDragRegion: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        WindowDragNSView()
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

private final class WindowDragNSView: NSView {
    override var mouseDownCanMoveWindow: Bool { true }

    /// Never claim hits — lets SwiftUI buttons receive clicks. Empty title-strip
    /// areas still drag because AppKit consults `mouseDownCanMoveWindow` on the
    /// view under the cursor when the event isn't eaten by a control.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

// MARK: - Hide / restore system buttons

enum DTSystemTrafficLights {
    /// Hide the stock macOS traffic lights so they cannot steal hits from our strip.
    /// Root cause of dead custom close/min: the theme-frame button container was left
    /// at `alphaValue = 0` (still hit-testable) while `performClose` no-ops on a hidden
    /// close button. Hide the container outright and disable the buttons.
    static func hide(on window: NSWindow) {
        for type: NSWindow.ButtonType in [.closeButton, .miniaturizeButton, .zoomButton] {
            if let button = window.standardWindowButton(type) {
                button.isHidden = true
                button.alphaValue = 0
                button.isEnabled = false
            }
        }
        if let container = window.standardWindowButton(.closeButton)?.superview {
            container.isHidden = true
            container.alphaValue = 0
        }
    }

    static func show(on window: NSWindow) {
        for type: NSWindow.ButtonType in [.closeButton, .miniaturizeButton, .zoomButton] {
            if let button = window.standardWindowButton(type) {
                button.isHidden = false
                button.alphaValue = 1
                button.isEnabled = true
            }
        }
        if let container = window.standardWindowButton(.closeButton)?.superview {
            container.isHidden = false
            container.alphaValue = 1
        }
    }
}

/// Finds the hosting NSWindow for a SwiftUI subtree (menu-bar panel polish).
struct HostWindowAccessor: NSViewRepresentable {
    var onResolve: (NSWindow) -> Void

    final class Coordinator {
        var polishedObjectID: ObjectIdentifier?
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { [weak view] in
            guard let window = view?.window else { return }
            let id = ObjectIdentifier(window)
            guard context.coordinator.polishedObjectID != id else { return }
            context.coordinator.polishedObjectID = id
            onResolve(window)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async { [weak nsView] in
            guard let window = nsView?.window else { return }
            let id = ObjectIdentifier(window)
            guard context.coordinator.polishedObjectID != id else { return }
            context.coordinator.polishedObjectID = id
            onResolve(window)
        }
    }
}
