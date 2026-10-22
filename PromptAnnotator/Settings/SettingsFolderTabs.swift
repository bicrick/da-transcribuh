import SwiftUI

/// Chrome-style folder tabs across the top of Settings.
///
/// Intrinsic height only. Do not put flexible `Color`/`Spacer` children that can grow
/// vertically inside the shelf HStack — a bare `Color.clear.frame(width:)` greedily
/// takes the VStack’s leftover height and the shelf fill paints a huge empty band.
///
/// Selected tab merges into the page (`Ink.front` fill). The shelf rule and the
/// selected tab outline are one continuous 1pt stroke: rule → up left foot/side →
/// across the top → down right → rule. Unselected tabs share one height/baseline
/// and sit on the rule.
struct SettingsFolderTabs: View {
    @Binding var selection: SettingsPage
    var onSearch: (() -> Void)? = nil

    private var tabHeight: CGFloat { Ink.folderTabHeight }
    /// Top pad + tab face. Keep the shelf from ever stretching.
    private var shelfHeight: CGFloat { Ink.space2 + tabHeight }
    /// How far the selected fill bleeds over the shelf line into the page (fill only).
    private let selectedBleed: CGFloat = 1

    @State private var selectedFrame: CGRect = .null

    var body: some View {
        HStack(alignment: .bottom, spacing: 0) {
            ForEach(Array(SettingsPage.tabGroups.enumerated()), id: \.offset) { groupIndex, group in
                if groupIndex > 0 {
                    Color.clear
                        .frame(width: Ink.tabGroupGap, height: 1)
                }
                ForEach(Array(group.enumerated()), id: \.element.id) { tabIndex, page in
                    if tabIndex > 0 {
                        // Tight gap — feet stay distinct without trapezoid flare tricks.
                        Color.clear
                            .frame(width: 2, height: 1)
                    }
                    tab(page)
                }
            }
            Spacer(minLength: Ink.space2)
            if let onSearch {
                SettingsSearchAffordance(action: onSearch)
                    .padding(.bottom, 6)
            }
        }
        .padding(.horizontal, Ink.pageSide)
        .padding(.top, Ink.space2)
        .frame(maxWidth: .infinity, alignment: .bottomLeading)
        .fixedSize(horizontal: false, vertical: true)
        .frame(height: shelfHeight, alignment: .bottom)
        .coordinateSpace(name: ShelfSpace.name)
        .background {
            ZStack(alignment: .bottom) {
                Ink.fill
                // Single path: full-width rule joined to the selected tab outline,
                // stroked in the selected tab’s accent (animates on tab change).
                SelectedTabShelfStroke(gap: selectedFrame)
                    .stroke(selection.tabAccent, lineWidth: 1)
                    .frame(height: shelfHeight)
                    .allowsHitTesting(false)
                    .animation(.easeInOut(duration: 0.15), value: selection)
            }
        }
        .onPreferenceChange(SelectedTabFrameKey.self) { frame in
            selectedFrame = frame ?? .null
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Settings")
    }

    private func tab(_ page: SettingsPage) -> some View {
        let selected = selection == page
        return Button {
            selection = page
        } label: {
            HStack(spacing: Ink.space1 + 1) {
                Image(systemName: page.symbol)
                    .font(.system(size: 10, weight: .bold))
                    .symbolRenderingMode(.monochrome)
                Text(page.title)
                    .font(Ink.folderTabFont)
                    .lineLimit(1)
            }
            .foregroundStyle(selected ? Ink.label : Ink.secondary)
            .padding(.horizontal, Ink.space3)
            // Room for Chrome feet so the shape isn’t clipped.
            .padding(.horizontal, FolderTabShape.foot)
            .frame(height: tabHeight)
            .background {
                FolderTabShape(closeBottom: !selected)
                    .fill(selected ? Ink.front : Ink.fill)
            }
            .overlay {
                // Unselected only — selected outline is the accent shelf stroke.
                if !selected {
                    FolderTabShape(closeBottom: true)
                        .stroke(Ink.hairline, lineWidth: 1)
                }
            }
            .overlay(alignment: .top) {
                // Selected: colored outline is enough — no inner stripe.
                // Unselected: quiet tick so tabs stay identifiable before selection.
                if !selected {
                    Rectangle()
                        .fill(page.tabAccent)
                        .frame(height: 1)
                        .padding(.horizontal, FolderTabShape.foot + FolderTabShape.corner)
                        .padding(.top, 3)
                        .opacity(0.45)
                }
            }
            // Fill bleed only — stroke stays on the shelf baseline via the shared path.
            .background(alignment: .bottom) {
                if selected {
                    Ink.front
                        .frame(height: selectedBleed)
                        .offset(y: selectedBleed)
                        .padding(.horizontal, FolderTabShape.foot)
                }
            }
            .background {
                if selected {
                    GeometryReader { geo in
                        Color.clear.preference(
                            key: SelectedTabFrameKey.self,
                            value: geo.frame(in: .named(ShelfSpace.name))
                        )
                    }
                }
            }
        }
        .buttonStyle(.plain)
        .zIndex(selected ? 1 : 0)
        .accessibilityLabel(page.pageTitle)
        .accessibilityAddTraits(selected ? [.isSelected, .isButton] : .isButton)
        .keyboardShortcut(page.keyboardDigit, modifiers: .command)
    }
}

// MARK: - Shelf space + selected frame

private enum ShelfSpace {
    static let name = "settings.folderTabShelf"
}

private struct SelectedTabFrameKey: PreferenceKey {
    static var defaultValue: CGRect? = nil

    static func reduce(value: inout CGRect?, nextValue: () -> CGRect?) {
        if let next = nextValue() {
            value = next
        }
    }
}

/// One continuous path: left rule → selected Chrome-tab outline → right rule.
/// Pixel-aligned (centerline on .5). Stroke color comes from the caller (selected accent).
private struct SelectedTabShelfStroke: Shape {
    var gap: CGRect

    func path(in rect: CGRect) -> Path {
        let y = rect.maxY - 0.5
        var path = Path()

        if gap.isNull || gap.isEmpty || gap.width <= 2 * FolderTabShape.foot {
            path.move(to: CGPoint(x: rect.minX, y: y))
            path.addLine(to: CGPoint(x: rect.maxX, y: y))
            return path
        }

        let tab = CGRect(
            x: gap.minX,
            y: gap.minY,
            width: gap.width,
            height: max(0, y + 0.5 - gap.minY)
        )
        path.move(to: CGPoint(x: rect.minX, y: y))
        path.addLine(to: CGPoint(x: tab.minX, y: y))
        FolderTabShape.appendOpenOutline(to: &path, in: tab, shelfY: y, moveToStart: false)
        path.addLine(to: CGPoint(x: rect.maxX, y: y))
        return path
    }
}

// MARK: - Chrome-style tab silhouette

/// Chrome-like tab: fixed geometry for every label width.
/// Rounded top corners (`corner`) and concave outward feet (`foot`) at the shelf.
/// Rect bounds include the feet; the rectangular body sits between `foot` and `width - foot`.
struct FolderTabShape: Shape {
    /// Rounded top-corner radius (pt). Identical for every tab.
    static let corner: CGFloat = 6
    /// Concave foot radius where the tab meets the shelf (pt).
    static let foot: CGFloat = 6

    /// When true, close along the shelf baseline (unselected). Selected leaves bottom open.
    var closeBottom: Bool

    func path(in rect: CGRect) -> Path {
        var path = Path()
        Self.appendOpenOutline(to: &path, in: rect, shelfY: rect.maxY, moveToStart: true)
        if closeBottom {
            path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
            path.closeSubpath()
        }
        return path
    }

    /// Open outline starting at the left foot tip on `shelfY` and ending at the right foot tip.
    /// Shared by fill shapes and the continuous shelf stroke so joints match exactly.
    /// When `moveToStart` is false, the caller must already be at the left foot tip.
    static func appendOpenOutline(
        to path: inout Path,
        in rect: CGRect,
        shelfY: CGFloat,
        moveToStart: Bool = true
    ) {
        let r = corner
        let f = foot
        let bodyLeft = rect.minX + f
        let bodyRight = rect.maxX - f
        let top = rect.minY
        // Keep feet from collapsing on very narrow tabs.
        let safeR = min(r, max(0, (bodyRight - bodyLeft) / 2), max(0, (shelfY - top) / 2))

        if moveToStart {
            path.move(to: CGPoint(x: rect.minX, y: shelfY))
        }

        // Concave left foot: circle centered at bodyLeft on the shelf.
        // Arc from west (foot tip) to north (up the body wall).
        path.addArc(
            center: CGPoint(x: bodyLeft, y: shelfY),
            radius: f,
            startAngle: .degrees(180),
            endAngle: .degrees(270),
            clockwise: false
        )

        // Left wall up to the top corner.
        path.addLine(to: CGPoint(x: bodyLeft, y: top + safeR))

        // Top-left rounded corner.
        path.addArc(
            center: CGPoint(x: bodyLeft + safeR, y: top + safeR),
            radius: safeR,
            startAngle: .degrees(180),
            endAngle: .degrees(270),
            clockwise: false
        )

        // Flat top.
        path.addLine(to: CGPoint(x: bodyRight - safeR, y: top))

        // Top-right rounded corner.
        path.addArc(
            center: CGPoint(x: bodyRight - safeR, y: top + safeR),
            radius: safeR,
            startAngle: .degrees(270),
            endAngle: .degrees(0),
            clockwise: false
        )

        // Right wall down to the foot.
        path.addLine(to: CGPoint(x: bodyRight, y: shelfY - f))

        // Concave right foot: north → east onto the shelf.
        path.addArc(
            center: CGPoint(x: bodyRight, y: shelfY),
            radius: f,
            startAngle: .degrees(270),
            endAngle: .degrees(0),
            clockwise: false
        )
    }
}

extension SettingsPage {
    /// Groups: primary (Home / Appearance / History), speech (Models), app plumbing.
    static var tabGroups: [[SettingsPage]] {
        [
            [.home, .appearance, .history],
            [.model],
            [.configuration, .sound, .performance],
        ]
    }

    /// Left-to-right order matching the folder tabs (for ←/→).
    static var tabOrder: [SettingsPage] { tabGroups.flatMap { $0 } }

    var keyboardDigit: KeyEquivalent {
        switch self {
        case .home: return "1"
        case .appearance: return "2"
        case .history: return "3"
        case .model: return "4"
        case .configuration: return "5"
        case .sound: return "6"
        case .performance: return "7"
        }
    }

    /// Paint accent for the continuous selected shelf stroke (and quiet unselected ticks).
    /// Lifted slightly in dark so the 1pt path stays readable on graphite.
    var tabAccent: Color {
        switch self {
        case .home: return Ink.tabStrokeRed
        case .appearance: return Ink.tabStrokePurple
        case .history: return Ink.tabStrokeBlue
        case .model: return Ink.tabStrokeOrange
        case .configuration: return Ink.tabStrokeGreen
        case .sound: return Ink.tabStrokeTeal
        case .performance: return Ink.tabStrokePink
        }
    }
}
