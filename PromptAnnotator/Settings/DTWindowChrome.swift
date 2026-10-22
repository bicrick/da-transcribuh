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
                    .zIndex(1)
                Spacer(minLength: 0)
                InkPaintSwatchStrip(size: 9, limit: 10)
                    .padding(.trailing, Ink.space4)
                    .allowsHitTesting(false)
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
            Rectangle()
                .fill(Ink.label)
                .frame(height: 2)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("da transcribuh window")
    }
}

// MARK: - Traffic lights

private enum DTWindowButtonKind {
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

    func perform(on window: NSWindow) {
        switch self {
        case .close:
            window.performClose(nil)
        case .miniaturize:
            window.miniaturize(nil)
        case .zoom:
            window.zoom(nil)
        }
    }
}

struct DTTrafficLights: View {
    @State private var windowIsKey = true

    var body: some View {
        HStack(spacing: Ink.space2) {
            DTTrafficLight(kind: .close, isKey: windowIsKey)
            DTTrafficLight(kind: .miniaturize, isKey: windowIsKey)
            DTTrafficLight(kind: .zoom, isKey: windowIsKey)
        }
        .accessibilityElement(children: .contain)
        .onAppear { refreshKey() }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { note in
            if note.object as AnyObject? === SettingsPresenter.shared.attachedWindow {
                windowIsKey = true
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didResignKeyNotification)) { note in
            if note.object as AnyObject? === SettingsPresenter.shared.attachedWindow {
                windowIsKey = false
            }
        }
    }

    private func refreshKey() {
        windowIsKey = SettingsPresenter.shared.attachedWindow?.isKeyWindow ?? true
    }
}

private struct DTTrafficLight: View {
    let kind: DTWindowButtonKind
    var isKey: Bool
    @State private var hovering = false

    private let diameter: CGFloat = 12

    var body: some View {
        Button {
            guard let window = SettingsPresenter.shared.attachedWindow else { return }
            kind.perform(on: window)
        } label: {
            ZStack {
                Circle()
                    .fill(isKey ? kind.paintFill : Ink.window)
                Circle()
                    .strokeBorder(Ink.label, lineWidth: 1)
                if hovering {
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
        .onHover { hovering = $0 }
        .help(kind.accessibilityLabel)
        .accessibilityLabel(kind.accessibilityLabel)
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
struct WindowDragRegion: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        WindowDragNSView()
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

private final class WindowDragNSView: NSView {
    override var mouseDownCanMoveWindow: Bool { true }
}

// MARK: - Hide / restore system buttons

enum DTSystemTrafficLights {
    /// Hide the stock macOS traffic lights. Safe no-op if buttons are missing.
    static func hide(on window: NSWindow) {
        for type: NSWindow.ButtonType in [.closeButton, .miniaturizeButton, .zoomButton] {
            window.standardWindowButton(type)?.isHidden = true
            window.standardWindowButton(type)?.alphaValue = 0
        }
        // Soften the system titlebar chrome so our strip reads as the top edge.
        // Fall back quietly if the hierarchy differs across macOS builds.
        if let container = window.standardWindowButton(.closeButton)?.superview {
            container.alphaValue = 0
        }
    }

    static func show(on window: NSWindow) {
        for type: NSWindow.ButtonType in [.closeButton, .miniaturizeButton, .zoomButton] {
            window.standardWindowButton(type)?.isHidden = false
            window.standardWindowButton(type)?.alphaValue = 1
        }
        if let container = window.standardWindowButton(.closeButton)?.superview {
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
