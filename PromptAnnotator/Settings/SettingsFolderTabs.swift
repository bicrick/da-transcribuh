import SwiftUI

/// Paint-style folder tabs across the top of Settings.
///
/// Square faces, `Ink.stroke` (2pt) accent outlines, **no bevels**. Layout is
/// **selection-invariant**. Selected outline + continuous shelf are one path
/// drawn on top (full accent, open bottom merging into the page). Unselected
/// tabs get the same 2pt accent weight on the face and rest on the shelf.
struct SettingsFolderTabs: View {
    @Binding var selection: SettingsPage
    var onSearch: (() -> Void)? = nil

    private var tabHeight: CGFloat { Ink.folderTabHeight }
    private var shelfHeight: CGFloat { Ink.space2 + tabHeight }
    private var selectedBleed: CGFloat { Ink.stroke }

    @State private var selectedFrame: CGRect = .null

    var body: some View {
        ZStack {
            // Tabs stay bottom-aligned on the shelf (unchanged positions / sizes).
            HStack(alignment: .bottom, spacing: Ink.tabGap) {
                ForEach(SettingsPage.tabOrder) { page in
                    tab(page)
                }
                Spacer(minLength: Ink.space2)
            }
            .padding(.horizontal, Ink.pageSide)
            .padding(.top, Ink.space2)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)

            // ⌘K centered in the strip band (top divider ↔ top of accent shelf).
            if let onSearch {
                HStack(spacing: 0) {
                    Spacer(minLength: 0)
                    SettingsSearchAffordance(action: onSearch)
                }
                .padding(.horizontal, Ink.pageSide)
                .padding(.bottom, Ink.stroke) // exclude shelf stroke from the centering band
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: shelfHeight)
        .coordinateSpace(name: ShelfSpace.name)
        .background {
            ZStack(alignment: .bottom) {
                // Tab row well; page color under the shelf stroke (no fill→front band).
                Ink.fill
                Ink.front
                    .frame(maxWidth: .infinity)
                    .frame(height: Ink.stroke)
            }
        }
        // Continuous shelf + selected U on TOP so stroke weight matches unselected faces
        // (never double-drawn, never hidden behind fill).
        .overlay(alignment: .bottom) {
            SelectedTabShelfStroke(gap: selectedFrame)
                .stroke(selection.tabAccent, lineWidth: Ink.stroke)
                .allowsHitTesting(false)
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
                // Unselected only — selected outline is the overlay shelf path (same 2pt).
                if !selected {
                    FolderTabShape(closeBottom: false)
                        .stroke(page.tabAccent, lineWidth: Ink.stroke)
                }
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
        }
        .buttonStyle(.plain)
        .zIndex(selected ? 1 : 0)
        .accessibilityLabel(page.pageTitle)
        .accessibilityAddTraits(selected ? [.isSelected, .isButton] : .isButton)
        .keyboardShortcut(page.keyboardDigit, modifiers: .command)
    }
}

// MARK: - Preference plumbing

private enum ShelfSpace {
    static let name = "SettingsFolderShelf"
}

enum FolderTabMetrics {
    /// Uniform gap between every tab — same as `Ink.tabGap`.
    static let intraGroupGap: CGFloat = Ink.tabGap
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
/// Pixel-centered for `Ink.stroke` at 1× / 2× so sides meet the shelf at whole-pixel corners.
/// Drawn once on top of the tab row — never doubles the selected edge.
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

/// Square folder-tab face (no rounded tops, no cove feet, no bevel).
struct FolderTabShape: Shape {
    static let corner: CGFloat = 0
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

    /// Ideal layout size for a tab (selection-invariant).
    static func layoutSize(titleWidth: CGFloat, height: CGFloat = Ink.folderTabHeight) -> CGSize {
        let width = 10 + (Ink.space1 + 1) + titleWidth + Ink.space3 * 2
        return CGSize(width: width, height: height)
    }
}

extension SettingsPage {
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
