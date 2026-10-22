import SwiftUI

/// Manila-folder divider tabs across the top of Settings — replaces the toolbox sidebar.
///
/// Intrinsic height only. Do not put flexible `Color`/`Spacer` children that can grow
/// vertically inside the shelf HStack — a bare `Color.clear.frame(width:)` greedily
/// takes the VStack’s leftover height and the shelf fill paints a huge empty band.
///
/// Selected tab merges into the page: fill is `Ink.front`, the shelf hairline is
/// interrupted under it, and the tab sits 1pt lower so side borders flow into the
/// content edge with no seam (light + graphite).
struct SettingsFolderTabs: View {
    @Binding var selection: SettingsPage
    var onSearch: (() -> Void)? = nil

    private var tabHeight: CGFloat { Ink.folderTabHeight }
    private let unselectedInset: CGFloat = 3
    /// Top pad + selected tab face. Keep the shelf from ever stretching.
    private var shelfHeight: CGFloat { Ink.space2 + tabHeight }
    /// How far the selected tab bleeds over the shelf hairline into the page.
    private let selectedBleed: CGFloat = 1

    @State private var selectedFrame: CGRect = .null

    var body: some View {
        HStack(alignment: .bottom, spacing: 0) {
            ForEach(Array(SettingsPage.tabGroups.enumerated()), id: \.offset) { groupIndex, group in
                if groupIndex > 0 {
                    // Fixed-size gap — never a flexible Color (expands vertically).
                    Color.clear
                        .frame(width: Ink.tabGroupGap, height: 1)
                }
                ForEach(Array(group.enumerated()), id: \.element.id) { tabIndex, page in
                    if tabIndex > 0 {
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
        // Shelf fill + hairline with a gap under the selected tab (drawn behind tabs).
        .background {
            ZStack(alignment: .bottom) {
                Ink.fill
                ShelfHairline(gap: selectedFrame)
                    .frame(height: 1)
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
            .frame(height: selected ? tabHeight : tabHeight - unselectedInset)
            .background {
                // Selected = page face so it merges with content below.
                FolderTabShape(selected: selected)
                    .fill(selected ? Ink.front : Ink.fill)
            }
            .overlay {
                FolderTabShape(selected: selected)
                    .stroke(Ink.label, lineWidth: 1)
            }
            .overlay(alignment: .top) {
                // Per-tab Paint accent: full stripe when selected; quiet tick when not.
                Rectangle()
                    .fill(page.tabAccent)
                    .frame(height: selected ? 2 : 1)
                    .padding(.horizontal, selected ? 10 : 14)
                    .padding(.top, selected ? 1 : 2)
                    .opacity(selected ? 1 : 0.45)
            }
            .padding(.bottom, selected ? 0 : unselectedInset)
            // Bleed 1pt over the hairline so fill + side strokes meet the page with no seam.
            .offset(y: selected ? selectedBleed : 0)
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

// MARK: - Shelf hairline (gap under selected tab)

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

/// Continuous shelf rule with a clean gap exactly under the selected tab frame.
private struct ShelfHairline: View {
    var gap: CGRect

    var body: some View {
        Canvas { context, size in
            let y = size.height - 0.5
            var path = Path()
            if gap.isNull || gap.isEmpty || gap.width <= 0 {
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: size.width, y: y))
            } else {
                let left = max(0, gap.minX)
                let right = min(size.width, gap.maxX)
                if left > 0 {
                    path.move(to: CGPoint(x: 0, y: y))
                    path.addLine(to: CGPoint(x: left, y: y))
                }
                if right < size.width {
                    path.move(to: CGPoint(x: right, y: y))
                    path.addLine(to: CGPoint(x: size.width, y: y))
                }
            }
            context.stroke(path, with: .color(Ink.hairline), lineWidth: 1)
        }
        .allowsHitTesting(false)
    }
}

// MARK: - Tab silhouette

/// Raised folder tab: angled shoulders, flat top. Selected omits the bottom edge so
/// the face merges with the page (no seam under the selected tab).
struct FolderTabShape: Shape {
    var selected: Bool

    func path(in rect: CGRect) -> Path {
        let r: CGFloat = 3
        let flare: CGFloat = 5
        var path = Path()
        // Start bottom-left (under the shelf when selected).
        path.move(to: CGPoint(x: 0, y: rect.maxY))
        path.addLine(to: CGPoint(x: flare, y: r))
        path.addQuadCurve(
            to: CGPoint(x: flare + r, y: 0),
            control: CGPoint(x: flare, y: 0)
        )
        path.addLine(to: CGPoint(x: rect.maxX - flare - r, y: 0))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX - flare, y: r),
            control: CGPoint(x: rect.maxX - flare, y: 0)
        )
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        if !selected {
            path.addLine(to: CGPoint(x: 0, y: rect.maxY))
            path.closeSubpath()
        }
        // Selected: leave bottom open so the stroke doesn’t draw a seam.
        return path
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

    /// Quiet Paint accent for the folder-tab top stripe (moved off Home stats).
    var tabAccent: Color {
        switch self {
        case .home: return Ink.paintRed
        case .appearance: return Ink.paintOrange
        case .history: return Ink.paintBlue
        case .model: return Ink.paintMagenta
        case .configuration: return Ink.paintGreen
        case .sound: return Ink.paintTeal
        case .performance: return Ink.paintPink
        }
    }
}
