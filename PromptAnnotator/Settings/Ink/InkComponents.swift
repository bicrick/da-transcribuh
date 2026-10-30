import AppKit
import SwiftUI

// MARK: - Wordmark (lowercase name only — no trailing block cursor)

struct DTWordmark: View {
    var size: CGFloat = 11

    var body: some View {
        Text("da transcribuh")
            .font(Ink.mono(size))
            .foregroundStyle(Ink.label)
            .tracking(0)
            .accessibilityLabel("da transcribuh")
    }
}

// MARK: - Double pane (recording island / selected chrome)

/// Hard offset “double pane” — shared by island + selected chrome:
/// `Ink.label` face border (`Ink.stroke`), `Ink.bevel` solid offset at `Ink.bevelOffset`,
/// gutter reserved so the offset never clips. Bevel is theme-inverted (black ↔ `#F2F2F2`).
struct InkDoublePaneModifier: ViewModifier {
    var cornerRadius: CGFloat = Ink.sidebarRowRadius
    var borderWidth: CGFloat = Ink.stroke
    var fill: Color = Ink.front
    /// Pressed/selected: pane sits flush and the face slides into the gutter.
    var pressed: Bool = false

    func body(content: Content) -> some View {
        content
            .background(
                fill,
                in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Ink.label, lineWidth: borderWidth)
            )
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Ink.bevel)
                    .offset(
                        x: pressed ? 0 : Ink.bevelOffset,
                        y: pressed ? 0 : Ink.bevelOffset
                    )
            )
            .offset(x: pressed ? Ink.bevelOffset : 0, y: pressed ? Ink.bevelOffset : 0)
            .padding(.trailing, Ink.bevelOffset)
            .padding(.bottom, Ink.bevelOffset)
    }
}

extension View {
    /// Shared double-pane chrome (recording island + selected chrome).
    func inkDoublePane(
        cornerRadius: CGFloat = Ink.sidebarRowRadius,
        borderWidth: CGFloat = Ink.stroke,
        fill: Color = Ink.front,
        pressed: Bool = false
    ) -> some View {
        modifier(
            InkDoublePaneModifier(
                cornerRadius: cornerRadius,
                borderWidth: borderWidth,
                fill: fill,
                pressed: pressed
            )
        )
    }
}

// MARK: - Card / Tile

struct InkCard<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Ink.card, in: RoundedRectangle(cornerRadius: Ink.cardRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Ink.cardRadius, style: .continuous)
                .strokeBorder(Ink.label, lineWidth: Ink.lineWidth)
        )
    }
}

struct InkTile<Content: View>: View {
    var selected: Bool = false
    /// Off for tiles that only show data (Performance), so they don't invite a click.
    var hoverable: Bool = true
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(Ink.cardPad)
            .background(Ink.card, in: RoundedRectangle(cornerRadius: Ink.tileRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Ink.tileRadius, style: .continuous)
                    .strokeBorder(Ink.label, lineWidth: selected ? Ink.selectedBorder : Ink.lineWidth)
            )
            // Selected tiles rise off their bevel; the rest just take the tint.
            .retroHover(
                in: RoundedRectangle(cornerRadius: Ink.tileRadius, style: .continuous),
                lift: selected ? .upLeft : .none,
                enabled: hoverable
            )
            .background(alignment: .topLeading) {
                // Hard shadow is paint-only — always reserved via outer padding so
                // selection never shifts the card in a grid. Drawn after the hover
                // so it stays put while the face lifts.
                if selected {
                    RoundedRectangle(cornerRadius: Ink.tileRadius, style: .continuous)
                        .fill(Ink.bevel)
                        .offset(x: Ink.bevelOffset, y: Ink.bevelOffset)
                }
            }
            // Reserve shadow gutter on every tile (selected or not) so tops/heights line up.
            .padding(.trailing, Ink.bevelOffset)
            .padding(.bottom, Ink.bevelOffset)
    }
}

// MARK: - Typography / section

struct InkSectionHeader: View {
    var title: String
    var caption: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: Ink.titleDescGap) {
            HStack(spacing: Ink.space2) {
                Text(title.uppercased())
                    .font(Ink.sectionTitleFont)
                    .tracking(0.6)
                    .foregroundStyle(Ink.label)
                Rectangle()
                    .fill(Ink.label)
                    .frame(height: 1)
            }
            if let caption {
                Text(caption)
                    .font(Ink.captionFont)
                    .foregroundStyle(Ink.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

struct InkEyebrow: View {
    var text: String

    var body: some View {
        Text(text.uppercased())
            .font(Ink.eyebrowFont)
            .tracking(0.6)
            .foregroundStyle(Ink.label)
    }
}

struct InkBadge: View {
    var text: String
    var accented: Bool = false

    var body: some View {
        Text(text)
            .font(Ink.badgeFont)
            .foregroundStyle(accented ? Ink.onPrimary : Ink.label)
            .padding(.horizontal, 5)
            .frame(height: 17)
            .background(
                (accented ? Ink.primaryFill : Color.clear),
                in: RoundedRectangle(cornerRadius: 2, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .strokeBorder(Ink.controlBorder, lineWidth: Ink.stroke)
            )
    }
}

struct InkDivider: View {
    var leading: CGFloat = Ink.rowHPad

    var body: some View {
        Rectangle()
            .fill(Ink.hairline)
            .frame(height: 1)
            .padding(.leading, leading)
    }
}

struct InkIconChip: View {
    var systemName: String
    var tint: Color = Ink.label

    var body: some View {
        Image(systemName: systemName)
            .font(Ink.labelFont)
            .foregroundStyle(tint)
            .frame(width: 28, height: 28)
            .overlay(
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .strokeBorder(Ink.label, lineWidth: Ink.stroke)
            )
    }
}

// MARK: - Controls

struct InkKeycap: View {
    var label: String
    var compact: Bool = false

    var body: some View {
        keycapLabel
            .foregroundStyle(Ink.label)
            .padding(.horizontal, compact ? 6 : 7)
            .frame(minWidth: compact ? 22 : 26, minHeight: compact ? 22 : 26)
            .background(Ink.keycap, in: RoundedRectangle(cornerRadius: Ink.keycapRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Ink.keycapRadius, style: .continuous)
                    .strokeBorder(Ink.controlBorder, lineWidth: Ink.stroke)
            )
            .background(
                RoundedRectangle(cornerRadius: Ink.keycapRadius, style: .continuous)
                    .fill(Ink.bevel)
                    .offset(y: Ink.bevelOffset)
            )
    }

    @ViewBuilder
    private var keycapLabel: some View {
        let point: CGFloat = compact ? 11 : 13
        if let glyph = InkMissingGlyph(label) {
            InkMissingGlyphView(glyph: glyph)
                .frame(width: point, height: point)
        } else {
            Text(label)
                .font(compact ? Ink.keycapCompactFont : Ink.keycapFont)
        }
    }
}

struct InkKeycapRow: View {
    var keys: [String]
    var compact: Bool = false

    var body: some View {
        HStack(spacing: compact ? 4 : 6) {
            ForEach(Array(keys.enumerated()), id: \.offset) { _, key in
                InkKeycap(label: key, compact: compact)
            }
        }
    }
}

/// Home Start-row chord editor — same `ShortcutCapture` + `AppSettings.setChord` as General.
/// Muted “click to rebind” hint sits left of the keycaps (does not shift Start).
/// Hover: label border + tint + pointing hand. Click to capture; Esc cancels;
/// Delete restores fn. Conflicts show as a brief red caption under the caps.
struct HomeChordEditor: View {
    @ObservedObject var settings: AppSettings
    @State private var listening = false
    @State private var message: String?

    var body: some View {
        VStack(alignment: .trailing, spacing: Ink.space1) {
            HStack(alignment: .center, spacing: Ink.space2) {
                Text(listening ? "press keys… esc to cancel" : "click to rebind")
                    .font(Ink.mono(10))
                    .foregroundStyle(Ink.secondary)
                    .fixedSize()
                    .accessibilityHidden(true)

                Button {
                    beginListening()
                } label: {
                    ChordEditorFace(keys: settings.chord.keycaps, listening: listening)
                        .retroHover(
                            in: RoundedRectangle(cornerRadius: Ink.fieldRadius, style: .continuous),
                            enabled: !listening
                        )
                }
                .buttonStyle(.plain)
                .help(listening ? "Press a shortcut — Esc cancels, Delete restores fn" : "Edit recording shortcut")
                .accessibilityLabel(listening ? "Listening for shortcut" : "Recording shortcut \(settings.chord.display)")
                .accessibilityHint("Click to change the Start and stop shortcut")
            }

            if let message {
                Text(message)
                    .font(Ink.captionFont)
                    .foregroundStyle(Ink.error)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 280, alignment: .trailing)
                    .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.12), value: message)
        .background(
            ShortcutCapture(active: $listening) { event in
                let outcome = RecordingChordCapture.applyToggleEvent(event, settings: settings)
                listening = false
                message = RecordingChordCapture.message(for: outcome)
            }
        )
    }

    private func beginListening() {
        listening = true
        message = nil
    }
}

/// Keycaps with the editor outline: solid on hover, dashed while listening.
private struct ChordEditorFace: View {
    var keys: [String]
    var listening: Bool
    @Environment(\.retroHovered) private var hovered

    var body: some View {
        InkKeycapRow(keys: keys)
            .padding(3)
            .overlay(
                RoundedRectangle(cornerRadius: Ink.fieldRadius, style: .continuous)
                    .strokeBorder(
                        listening || hovered ? Ink.label : Color.clear,
                        style: StrokeStyle(lineWidth: Ink.stroke, dash: listening ? [4, 3] : [])
                    )
            )
    }
}

/// Paint keycap field — click, press a combo, it saves. Listening state pulses the border.
struct InkShortcutRecorder: View {
    var keys: [String]
    var listening: Bool
    var emptyLabel: String = "None"
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Group {
                if listening {
                    Text("press keys…")
                        .font(Ink.mono(11))
                        .foregroundStyle(Ink.secondary)
                        .padding(.horizontal, 10)
                        .frame(minHeight: 26)
                } else if keys.isEmpty {
                    Text(emptyLabel)
                        .font(Ink.mono(11))
                        .foregroundStyle(Ink.secondary)
                        .padding(.horizontal, 10)
                        .frame(minHeight: 26)
                } else {
                    InkKeycapRow(keys: keys, compact: true)
                }
            }
            .padding(4)
            .background(Ink.fill, in: RoundedRectangle(cornerRadius: Ink.fieldRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Ink.fieldRadius, style: .continuous)
                    .strokeBorder(listening ? Ink.paintCyan : Ink.controlBorder, lineWidth: Ink.stroke)
            )
            .retroHover(in: RoundedRectangle(cornerRadius: Ink.fieldRadius, style: .continuous), lift: .upLeft)
            .background(
                RoundedRectangle(cornerRadius: Ink.fieldRadius, style: .continuous)
                    .fill(Ink.bevel)
                    .offset(x: Ink.bevelOffset, y: Ink.bevelOffset)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(listening ? "Listening for shortcut" : keys.isEmpty ? emptyLabel : keys.joined(separator: " "))
        .accessibilityAddTraits(.isButton)
    }
}

/// 10-segment block meter for Speed / Quality / Size.
struct InkSegmentMeter: View {
    var label: String
    var fraction: Double
    var emphasized: Bool = false
    private let segments = 10
    /// Fixed label column so bars line up across sibling cards.
    static let labelWidth: CGFloat = 56

    var body: some View {
        HStack(spacing: Ink.space2) {
            Text(label)
                .font(Ink.headingFont)
                .foregroundStyle(Ink.secondary)
                .frame(width: Self.labelWidth, alignment: .leading)
            HStack(spacing: 2) {
                ForEach(0..<segments, id: \.self) { index in
                    Rectangle()
                        .fill(index < litCount ? Ink.label : Color.clear)
                        .overlay(Rectangle().strokeBorder(Ink.label, lineWidth: Ink.stroke))
                        .frame(height: 7)
                }
            }
            .frame(maxWidth: .infinity)
        }
        .opacity(emphasized ? 1 : 1)
    }

    private var litCount: Int {
        let clamped = min(1, max(0, fraction))
        return max(1, Int((clamped * Double(segments)).rounded()))
    }
}

struct InkProgressBar: View {
    var fraction: Double
    private let slots = 40

    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<slots, id: \.self) { index in
                Rectangle()
                    .fill(index < lit ? Ink.label : Color.clear)
                    .frame(width: 5, height: 6)
            }
            Spacer(minLength: 0)
        }
        .padding(Ink.space1 / 2)
        .frame(height: 12)
        .overlay(
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .strokeBorder(Ink.label, lineWidth: Ink.stroke)
        )
    }

    private var lit: Int {
        Int((min(1, max(0, fraction)) * Double(slots)).rounded())
    }
}

/// Square Paint radio: 2pt ink box, solid square dot when selected.
struct InkRadio: View {
    var selected: Bool
    @Environment(\.retroHovered) private var hovered

    var body: some View {
        ZStack {
            Rectangle()
                .fill(Ink.field)
            Rectangle()
                .fill(Ink.hoverTint)
                .opacity(hovered ? 1 : 0)
            Rectangle()
                .strokeBorder(Ink.label, lineWidth: Ink.stroke)
            if selected {
                Rectangle()
                    .fill(Ink.label)
                    .frame(width: 7, height: 7)
            }
        }
        .frame(width: 15, height: 15)
    }
}

struct InkCheck: View {
    var done: Bool
    @Environment(\.retroHovered) private var hovered

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 1, style: .continuous)
                .fill(done ? Ink.paintGreen : Ink.window)
            RoundedRectangle(cornerRadius: 1, style: .continuous)
                .fill(Ink.hoverTint)
                .opacity(hovered ? 1 : 0)
            RoundedRectangle(cornerRadius: 1, style: .continuous)
                .strokeBorder(Ink.label, lineWidth: Ink.stroke)
            if done {
                Image(systemName: "checkmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Ink.paintBlack)
            }
        }
        .frame(width: 16, height: 16)
    }
}


/// B/W switch — flat track + sliding block. Shared across Settings / onboarding.
struct InkToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button {
            configuration.isOn.toggle()
        } label: {
            HStack(alignment: .center, spacing: Ink.space3) {
                configuration.label
                Spacer(minLength: 0)
                InkSwitch(isOn: configuration.isOn)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(.isButton)
    }
}

struct InkSwitch: View {
    var isOn: Bool

    var body: some View {
        ZStack(alignment: isOn ? .trailing : .leading) {
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(isOn ? Ink.primaryFill : Ink.window)
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .strokeBorder(Ink.controlBorder, lineWidth: Ink.stroke)
            RoundedRectangle(cornerRadius: 1, style: .continuous)
                .fill(isOn ? Ink.onPrimary : Ink.label)
                .frame(width: 12, height: 12)
                .padding(Ink.space1 / 2)
        }
        .frame(width: 34, height: 18)
        .accessibilityHidden(true)
    }
}

/// Title + caption + B/W switch, terminal-row padding.
struct InkToggleRow: View {
    var title: String
    var detail: String?
    @Binding var isOn: Bool
    var enabled: Bool = true
    @Environment(\.settingsHighlightTitle) private var highlightTitle

    var body: some View {
        Toggle(isOn: $isOn) {
            VStack(alignment: .leading, spacing: Ink.titleDescGap) {
                Text(title)
                    .font(Ink.rowTitleFont)
                    .foregroundStyle(enabled ? Ink.label : Ink.tertiary)
                if let detail {
                    Text(detail)
                        .font(Ink.captionFont)
                        .foregroundStyle(Ink.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .toggleStyle(InkToggleStyle())
        .padding(.horizontal, Ink.rowHPad)
        .padding(.vertical, Ink.rowVPad)
        // The whole hovered row toggles, padding included, so the hand never lies.
        .contentShape(Rectangle())
        .onTapGesture { if enabled { isOn.toggle() } }
        .retroHover()
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.55)
        .background(highlightTitle == title ? Ink.paintYellow.opacity(0.55) : Color.clear)
        .animation(.easeOut(duration: 0.2), value: highlightTitle)
    }
}

/// Interactive checkbox (InkCheck) for discrete on/off rows.
struct InkCheckboxStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button {
            configuration.isOn.toggle()
        } label: {
            HStack(alignment: .top, spacing: Ink.space3) {
                InkCheck(done: configuration.isOn)
                    .padding(.top, 1)
                configuration.label
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
            .retroHover(tint: nil)
        }
        .buttonStyle(.plain)
    }
}

/// Flat B/W volume / fraction control (no system blue).
struct InkSlider: View {
    @Binding var value: Double
    var range: ClosedRange<Double> = 0...1
    var enabled: Bool = true
    /// Snap to this increment (nil = continuous).
    var step: Double? = nil
    /// VoiceOver value. Defaults to a percent of the range.
    var accessibilityText: ((Double) -> String)? = nil

    var body: some View {
        GeometryReader { geo in
            let width = max(1, geo.size.width)
            let fraction = CGFloat((value - range.lowerBound) / (range.upperBound - range.lowerBound))
            let thumb = max(0, min(1, fraction))
            ZStack(alignment: .leading) {
                Rectangle()
                    .fill(Ink.fill)
                    .overlay(Rectangle().strokeBorder(Ink.label, lineWidth: Ink.stroke))
                Rectangle()
                    .fill(Ink.label)
                    .frame(width: max(2, width * thumb))
                Rectangle()
                    .fill(Ink.window)
                    .overlay(Rectangle().strokeBorder(Ink.label, lineWidth: Ink.stroke))
                    .frame(width: 10, height: 16)
                    .offset(x: max(0, min(width - 10, width * thumb - 5)))
            }
            .frame(height: 16)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { drag in
                        guard enabled else { return }
                        let t = min(1, max(0, drag.location.x / width))
                        set(range.lowerBound + Double(t) * (range.upperBound - range.lowerBound))
                    }
            )
        }
        .frame(height: 16)
        .opacity(enabled ? 1 : 0.45)
        .allowsHitTesting(enabled)
        .accessibilityElement()
        .accessibilityValue(Text(accessibilityValue))
        .accessibilityAdjustableAction { direction in
            let delta = step ?? (range.upperBound - range.lowerBound) / 20
            switch direction {
            case .increment: set(value + delta)
            case .decrement: set(value - delta)
            @unknown default: break
            }
        }
    }

    private var accessibilityValue: String {
        if let accessibilityText { return accessibilityText(value) }
        let fraction = (value - range.lowerBound) / (range.upperBound - range.lowerBound)
        return "\(Int((fraction * 100).rounded())) percent"
    }

    private func set(_ raw: Double) {
        var next = min(range.upperBound, max(range.lowerBound, raw))
        if let step, step > 0 {
            next = range.lowerBound + ((next - range.lowerBound) / step).rounded() * step
            next = min(range.upperBound, next)
        }
        if next != value { value = next }
    }
}

/// Menu-style picker with Ink chrome (avoids system Form / blue).
///
/// Opens an AppKit menu whose items carry Departure Mono attributed titles,
/// so the open list matches the closed Paint button instead of the system font.
struct InkMenuPicker<Selection: Hashable>: View {
    var title: String
    @Binding var selection: Selection
    var options: [(Selection, String)]

    @State private var anchor = InkMenuAnchor()

    var body: some View {
        Button {
            anchor.popUp(
                options: options.map { ($0.1, $0.0 == selection) },
                onPick: { index in
                    guard options.indices.contains(index) else { return }
                    selection = options[index].0
                }
            )
        } label: {
            HStack(spacing: Ink.space2) {
                Text(labelText)
                    .font(Ink.buttonSmallFont)
                    .foregroundStyle(Ink.label)
                    .lineLimit(1)
                Text("▾")
                    .font(Ink.headingFont)
                    .foregroundStyle(Ink.label)
            }
            .padding(.horizontal, Ink.space3)
            .frame(height: 24)
            .background(Ink.window, in: RoundedRectangle(cornerRadius: Ink.buttonRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Ink.buttonRadius, style: .continuous)
                    .strokeBorder(Ink.label, lineWidth: Ink.stroke)
            )
            .contentShape(Rectangle())
            .retroHover(in: RoundedRectangle(cornerRadius: Ink.buttonRadius, style: .continuous))
        }
        .buttonStyle(.plain)
        .background(InkMenuAnchorView(anchor: anchor))
        .accessibilityLabel(title)
        .accessibilityValue(labelText)
    }

    private var labelText: String {
        options.first(where: { $0.0 == selection })?.1 ?? title
    }
}

/// Holds the AppKit view the Paint menu pops up under.
@MainActor
final class InkMenuAnchor {
    weak var view: NSView?

    func popUp(options: [(String, Bool)], onPick: @escaping (Int) -> Void) {
        let menu = NSMenu()
        menu.autoenablesItems = false
        let font = InkFontRegistrar.resolveNSFont(size: 12)
        let target = InkMenuTarget(onPick: onPick)
        for (index, option) in options.enumerated() {
            let item = NSMenuItem(title: option.0, action: #selector(InkMenuTarget.pick(_:)), keyEquivalent: "")
            item.attributedTitle = NSAttributedString(string: option.0, attributes: [.font: font])
            item.target = target
            item.tag = index
            item.state = option.1 ? .on : .off
            menu.addItem(item)
        }
        menu.minimumWidth = view?.bounds.width ?? 0
        // `popUp` tracks synchronously, so `target` outlives the menu session.
        if let view {
            menu.popUp(positioning: nil, at: NSPoint(x: 0, y: view.bounds.height + 4), in: view)
        } else {
            menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
        }
        withExtendedLifetime(target) {}
    }
}

private final class InkMenuTarget: NSObject {
    let onPick: (Int) -> Void
    init(onPick: @escaping (Int) -> Void) { self.onPick = onPick }
    @objc func pick(_ sender: NSMenuItem) { onPick(sender.tag) }
}

private struct InkMenuAnchorView: NSViewRepresentable {
    let anchor: InkMenuAnchor

    func makeNSView(context: Context) -> NSView {
        let view = InkFlippedAnchorNSView()
        anchor.view = view
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        anchor.view = nsView
    }
}

private final class InkFlippedAnchorNSView: NSView {
    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

/// Title / detail / trailing control — shared settings row.
struct InkSettingRow<Trailing: View>: View {
    var title: String
    var detail: String?
    @ViewBuilder var trailing: () -> Trailing
    @Environment(\.settingsHighlightTitle) private var highlightTitle

    var body: some View {
        HStack(alignment: .center, spacing: Ink.space3) {
            VStack(alignment: .leading, spacing: Ink.titleDescGap) {
                Text(title)
                    .font(Ink.rowTitleFont)
                    .foregroundStyle(Ink.label)
                if let detail {
                    Text(detail)
                        .font(Ink.captionFont)
                        .foregroundStyle(Ink.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            Spacer(minLength: Ink.space2)
            trailing()
        }
        .padding(.horizontal, Ink.rowHPad)
        .padding(.vertical, Ink.rowVPad)
        .background(highlightTitle == title ? Ink.paintYellow.opacity(0.55) : Color.clear)
        .animation(.easeOut(duration: 0.2), value: highlightTitle)
    }
}

struct InkStepDots: View {
    var current: Int
    var total: Int

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<total, id: \.self) { index in
                Rectangle()
                    .fill(index == current ? Ink.label : Color.clear)
                    .overlay(Rectangle().strokeBorder(index == current ? Ink.label : Ink.hairline, lineWidth: Ink.stroke))
                    .frame(width: 8, height: 8)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Step \(current + 1) of \(total)")
    }
}

/// Paint-style step rail for onboarding. Done steps are Paint green with a check,
/// the current step is Paint blue, steps ahead are outlined. The swatches are the
/// same hex in light and dark, so the rail reads the same in both.
struct InkStepRail: View {
    static let currentFill = Ink.paintBlue
    static let doneFill = Ink.paintGreen

    var current: Int
    var labels: [String]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(labels.enumerated()), id: \.offset) { index, label in
                stepCell(index: index, label: label)
                if index < labels.count - 1 {
                    Rectangle()
                        .fill(index < current ? Self.doneFill : Ink.hairline)
                        .frame(height: index < current ? 2 : 1)
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Step \(current + 1) of \(labels.count)")
    }

    private func stepCell(index: Int, label: String) -> some View {
        let state: StepState = {
            if index < current { return .done }
            if index == current { return .current }
            return .ahead
        }()
        return VStack(spacing: Ink.space1) {
            ZStack {
                Rectangle()
                    .fill(fill(for: state))
                    .overlay(Rectangle().strokeBorder(Ink.controlBorder, lineWidth: Ink.stroke))
                if state == .done {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .heavy))
                        .foregroundStyle(Ink.paintWhite)
                } else {
                    Text("\(index + 1)")
                        .font(Ink.headingFont)
                        .foregroundStyle(state == .current ? Ink.paintWhite : Ink.label)
                }
            }
            .frame(width: 22, height: 22)
            Text(label.uppercased())
                .font(Ink.headingFont)
                .foregroundStyle(state == .ahead ? Ink.tertiary : Ink.label)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(width: 56)
    }

    private func fill(for state: StepState) -> Color {
        switch state {
        case .done: return Self.doneFill
        case .current: return Self.currentFill
        case .ahead: return Ink.window
        }
    }

    private enum StepState {
        case done
        case current
        case ahead
    }
}

struct InkPrimaryButtonStyle: ButtonStyle {
    var large: Bool = true
    var enabled: Bool = true
    /// Set when the caller draws a hard bevel behind the button (Home Start),
    /// so the face rises off it on hover. Flat primaries only tint.
    var lift: RetroLift = .none

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(large ? Ink.buttonFont : Ink.buttonSmallFont)
            .foregroundStyle(enabled ? Ink.onPrimary : Ink.tertiary)
            .padding(.horizontal, large ? 15 : 11)
            .frame(height: large ? 30 : 24)
            .background(
                (enabled ? Ink.primaryFill : Ink.fill),
                in: RoundedRectangle(cornerRadius: Ink.buttonRadius, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Ink.buttonRadius, style: .continuous)
                    .strokeBorder(enabled ? Ink.controlBorder : Ink.tertiary, lineWidth: Ink.stroke)
            )
            .retroHover(
                in: RoundedRectangle(cornerRadius: Ink.buttonRadius, style: .continuous),
                tint: Ink.hoverTintOnPrimary,
                lift: lift,
                enabled: enabled
            )
            .opacity(configuration.isPressed ? 0.88 : 1)
    }
}

struct InkSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.inkSecondaryChrome(pressed: configuration.isPressed)
    }
}

extension View {
    /// The secondary button look, for labels that cannot be a Button (a footer
    /// action inside a tile Button) and for InkSecondaryButtonStyle itself.
    func inkSecondaryChrome(pressed: Bool = false) -> some View {
        self
            .font(Ink.buttonSmallFont)
            .foregroundStyle(Ink.label)
            .padding(.horizontal, Ink.space3)
            .frame(height: 24)
            .background(Ink.front, in: RoundedRectangle(cornerRadius: Ink.buttonRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Ink.buttonRadius, style: .continuous)
                    .strokeBorder(Ink.controlBorder, lineWidth: Ink.stroke)
            )
            // Face rises 1pt off the bevel on hover; the bevel below stays put.
            .retroHover(in: RoundedRectangle(cornerRadius: Ink.buttonRadius, style: .continuous), lift: .up)
            .background(
                RoundedRectangle(cornerRadius: Ink.buttonRadius, style: .continuous)
                    .fill(Ink.bevel)
                    .offset(y: Ink.bevelOffset)
            )
            .opacity(pressed ? 0.85 : 1)
    }
}

struct InkFieldBackground: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(Ink.field, in: RoundedRectangle(cornerRadius: Ink.fieldRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Ink.fieldRadius, style: .continuous)
                    .strokeBorder(Ink.label, lineWidth: Ink.stroke)
            )
    }
}

extension View {
    func inkFieldStyle() -> some View {
        modifier(InkFieldBackground())
    }

    func inkPageChrome() -> some View {
        self
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Ink.front)
            .tint(Ink.label)
    }
}

/// Welcome / Ready motif: waveform → arrow → block (B&W, no red ink stroke).
struct InkWavePenMotif: View {
    var inked: Bool = false
    var width: CGFloat = 360
    var height: CGFloat = 120

    private let barCount = 18

    var body: some View {
        HStack(spacing: 16) {
            Canvas { context, size in
                let midY = size.height * 0.5
                let gap: CGFloat = 3
                let barW: CGFloat = 4
                for i in 0..<barCount {
                    let t = Double(i) / Double(max(barCount - 1, 1))
                    let envelope = 0.25 + 0.75 * sin(t * .pi)
                    let h = max(4, size.height * 0.55 * envelope)
                    let x = CGFloat(i) * (barW + gap)
                    let rect = CGRect(x: x, y: midY - h / 2, width: barW, height: h)
                    // Welcome: outlined bars; Ready (`inked`): solid fill.
                    if inked {
                        context.fill(Path(rect), with: .color(Ink.label))
                    } else {
                        context.stroke(Path(rect), with: .color(Ink.label), lineWidth: Ink.stroke)
                    }
                }
            }
            .frame(width: 120, height: 48)

            Text("→")
                .font(Ink.titleFont)
                .foregroundStyle(Ink.label)

            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .strokeBorder(Ink.label, lineWidth: Ink.stroke)
                .frame(width: 44, height: 44)
                .overlay(
                    Rectangle()
                        .fill(Ink.label)
                        .frame(width: 14, height: 28)
                )
        }
        .frame(width: width, height: height)
        .frame(maxWidth: .infinity)
        .background(Ink.fill)
        .overlay(
            RoundedRectangle(cornerRadius: Ink.cardRadius, style: .continuous)
                .strokeBorder(Ink.hairline, lineWidth: Ink.stroke)
        )
        .accessibilityHidden(true)
    }
}

struct InkErrorBanner: View {
    var message: String

    var body: some View {
        HStack(alignment: .top, spacing: Ink.space3) {
            Text("!")
                .font(Ink.headingFont)
                .foregroundStyle(Ink.onPrimary)
                .frame(width: 16, height: 16)
                .background(Ink.primaryFill, in: RoundedRectangle(cornerRadius: Ink.buttonRadius, style: .continuous))
            Text(message)
                .font(Ink.captionFont)
                .foregroundStyle(Ink.label)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Ink.space3)
        .padding(.vertical, Ink.space2 + 1)
        .overlay(
            RoundedRectangle(cornerRadius: Ink.cardRadius, style: .continuous)
                .strokeBorder(Ink.label, lineWidth: Ink.stroke)
        )
    }
}

struct InkDashedEmpty: View {
    var title: String
    var detail: String
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: Ink.space3) {
            Text(title)
                .font(Ink.rowTitleFont)
                .foregroundStyle(Ink.label)
            Text(detail)
                .font(Ink.captionFont)
                .foregroundStyle(Ink.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(InkSecondaryButtonStyle())
            }
        }
        .padding(Ink.cardPad)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(
            RoundedRectangle(cornerRadius: Ink.cardRadius, style: .continuous)
                .strokeBorder(Ink.label, style: StrokeStyle(lineWidth: Ink.stroke, dash: [5, 4]))
        )
    }
}

// MARK: - Status bar

struct DTStatusBar: View {
    var cells: [String]
    var trailing: String
    /// When true, leading cell gets a flat Paint-red record square.
    var recording: Bool = false

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(cells.enumerated()), id: \.offset) { index, cell in
                HStack(spacing: Ink.space2 - 2) {
                    if index == 0 {
                        Rectangle()
                            .fill(recording ? Ink.record : Ink.label)
                            .overlay(Rectangle().strokeBorder(Ink.label, lineWidth: Ink.stroke))
                            .frame(width: 7, height: 7)
                    }
                    Text(cell)
                        .font(Ink.statusFont)
                        .foregroundStyle(Ink.label)
                }
                .padding(.horizontal, Ink.space3)
                .frame(height: Ink.statusBarHeight)
                Rectangle()
                    .fill(Ink.label)
                    .frame(width: 1, height: Ink.statusBarHeight)
            }
            Spacer(minLength: 0)
            Text(trailing)
                .font(Ink.statusFont)
                .foregroundStyle(Ink.secondary)
                .padding(.horizontal, Ink.space3)
                .frame(height: Ink.statusBarHeight)
        }
        .frame(height: Ink.statusBarHeight)
        .frame(maxWidth: .infinity)
        .overlay(alignment: .top) {
            Rectangle().fill(Ink.label).frame(height: 2)
        }
        .background(Ink.window)
    }
}

// Spec aliases
typealias MeterBar = InkSegmentMeter
typealias Keycap = InkKeycap
typealias StepDots = InkStepDots
typealias SectionHeader = InkSectionHeader
