import SwiftUI

/// Paint-style folder tabs across the top of Settings.
///
/// Square faces with `Ink.stroke` outlines and a hard `Ink.bevelOffset` ink bevel on
/// the **right** edge only (never below the shelf) — same language as bento cards.
/// Layout is **selection-invariant**: frames identical whether selected or not; only
/// paint changes. The full-width accent shelf joins the selected tab’s sides at
/// crisp right angles.
struct SettingsFolderTabs: View {
    @Binding var selection: SettingsPage
    var onSearch: (() -> Void)? = nil

    private var tabHeight: CGFloat { Ink.folderTabHeight }
    /// Top pad absorbs optional selected raise paint; layout height stays fixed.
    private var shelfHeight: CGFloat { Ink.space2 + tabHeight }
    private var selectedBleed: CGFloat { Ink.stroke }

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
                        Color.clear
                            .frame(width: FolderTabMetrics.intraGroupGap, height: 1)
                    }
                    tab(page)
                }
            }
            Spacer(minLength: Ink.space2)
            if let onSearch {
                SettingsSearchAffordance(action: onSearch)
                    .frame(height: tabHeight, alignment: .bottom)
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
                // Continuous accent shelf — on top of unselected bottoms, under selected fill bleed.
                SelectedTabShelfStroke(gap: selectedFrame)
                    .stroke(selection.tabAccent, lineWidth: Ink.stroke)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                    .allowsHitTesting(false)
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
            .frame(height: tabHeight)
            .background {
                FolderTabShape(closeBottom: true)
                    .fill(selected ? Ink.front : Ink.fill)
            }
            .overlay {
                // Unselected: muted accent, open bottom onto the shelf.
                // Selected outline is the continuous accent shelf stroke.
                if !selected {
                    FolderTabShape(closeBottom: false)
                        .stroke(page.tabAccent.opacity(0.55), lineWidth: Ink.stroke)
                }
            }
            .background(alignment: .topTrailing) {
                // Hard ink bevel on the RIGHT only — matches cards; never below the shelf.
                // Ink (not accent): same as bento cells / mark so the row reads as one system.
                Rectangle()
                    .fill(Ink.bevel)
                    .frame(width: Ink.bevelOffset)
                    .offset(x: Ink.bevelOffset)
            }
            .background(alignment: .bottom) {
                if selected {
                    Ink.front
                        .frame(height: selectedBleed)
                        .offset(y: selectedBleed)
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
            // Reserve bevel gutter so neighbors never shift when selection changes.
            .padding(.trailing, Ink.bevelOffset)
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

enum FolderTabMetrics {
    /// Gap between tab faces inside a group (selection-invariant).
    /// Bevel gutters live in each tab’s trailing padding, not in this gap.
    static let intraGroupGap: CGFloat = 2
}

private struct SelectedTabFrameKey: PreferenceKey {
    static var defaultValue: CGRect? = nil

    static func reduce(value: inout CGRect?, nextValue: () -> CGRect?) {
        if let next = nextValue() {
            value = next
        }
    }
}

/// Full-width accent rule joined to the selected tab’s square open outline.
/// `gap` is the face frame (excludes the trailing bevel gutter). Pixel-centered
/// for `Ink.stroke` at 1× / 2× so sides meet the shelf at whole-pixel corners.
private struct SelectedTabShelfStroke: Shape {
    var gap: CGRect

    func path(in rect: CGRect) -> Path {
        let stroke = Ink.stroke
        let y = rect.maxY - stroke / 2
        var path = Path()

        if gap.isNull || gap.isEmpty || gap.width <= 1 {
            path.move(to: CGPoint(x: rect.minX, y: y))
            path.addLine(to: CGPoint(x: rect.maxX, y: y))
            return path
        }

        // Center the vertical / top strokes on the face edges.
        let left = gap.minX
        let right = gap.maxX
        let top = gap.minY + stroke / 2

        path.move(to: CGPoint(x: rect.minX, y: y))
        path.addLine(to: CGPoint(x: left, y: y))
        path.addLine(to: CGPoint(x: left, y: top))
        path.addLine(to: CGPoint(x: right, y: top))
        path.addLine(to: CGPoint(x: right, y: y))
        path.addLine(to: CGPoint(x: rect.maxX, y: y))
        return path
    }
}

// MARK: - Square tab silhouette

/// Square folder-tab face (no rounded tops, no cove feet).
/// Open-bottom outlines let the continuous accent shelf show through.
struct FolderTabShape: Shape {
    /// Kept at 0 — square Paint chrome (tests assert this).
    static let corner: CGFloat = 0
    /// Legacy alias; bevel lives in `Ink.bevelOffset`, not a fillet.
    static let foot: CGFloat = 0

    var closeBottom: Bool = true

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        if closeBottom {
            path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
            path.closeSubpath()
        }
        return path
    }

    /// Ideal layout size for a tab **face** (selection-invariant; excludes bevel gutter).
    static func layoutSize(titleWidth: CGFloat, height: CGFloat = Ink.folderTabHeight) -> CGSize {
        let width = 10 + (Ink.space1 + 1) + titleWidth + Ink.space3 * 2
        return CGSize(width: width, height: height)
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

    /// Accent for selected shelf stroke / unselected outline (muted via opacity at the call site).
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
