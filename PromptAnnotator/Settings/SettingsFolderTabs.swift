import SwiftUI

/// Manila-folder divider tabs across the top of Settings — replaces the toolbox sidebar.
///
/// Intrinsic height only. Do not put flexible `Color`/`Spacer` children that can grow
/// vertically inside the shelf HStack — a bare `Color.clear.frame(width:)` greedily
/// takes the VStack’s leftover height and the shelf fill paints a huge empty band.
struct SettingsFolderTabs: View {
    @Binding var selection: SettingsPage
    var onSearch: (() -> Void)? = nil

    private var tabHeight: CGFloat { Ink.folderTabHeight }
    private let unselectedInset: CGFloat = 3
    /// Top pad + selected tab face. Keep the shelf from ever stretching.
    private var shelfHeight: CGFloat { Ink.space2 + tabHeight }

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
        // Ideal height only — refuse the VStack’s leftover flexible height.
        .fixedSize(horizontal: false, vertical: true)
        .frame(height: shelfHeight, alignment: .bottom)
        .background(Ink.fill)
        .overlay(alignment: .bottom) {
            // Shelf hairline — selected tab covers it so it reads as the front folder.
            Rectangle()
                .fill(Ink.hairline)
                .frame(height: 1)
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
                FolderTabShape(selected: selected)
                    .fill(selected ? Ink.front : Ink.fill)
            }
            .overlay {
                FolderTabShape(selected: selected)
                    .stroke(Ink.label, lineWidth: 1)
            }
            .overlay(alignment: .top) {
                if selected {
                    // Sparse accent — thin paint-red strip on the selected tab only.
                    Rectangle()
                        .fill(Ink.paintRed)
                        .frame(height: 2)
                        .padding(.horizontal, 10)
                        .padding(.top, 1)
                }
            }
            .padding(.bottom, selected ? 0 : unselectedInset)
            // Cover the shelf hairline when selected.
            .offset(y: selected ? 1 : 0)
        }
        .buttonStyle(.plain)
        .zIndex(selected ? 1 : 0)
        .accessibilityLabel(page.pageTitle)
        .accessibilityAddTraits(selected ? [.isSelected, .isButton] : .isButton)
        .keyboardShortcut(page.keyboardDigit, modifiers: .command)
    }
}

// MARK: - Tab silhouette

/// Raised folder tab: angled shoulders, flat top. Selected omits the bottom edge visually
/// by sitting over the shelf rule.
private struct FolderTabShape: Shape {
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
        // Selected: leave bottom open so the stroke doesn’t draw under the tab.
        return path
    }
}

extension SettingsPage {
    /// Groups with subtle gaps between Session / Speech / App clusters.
    static var tabGroups: [[SettingsPage]] {
        [
            [.home, .history, .recording],
            [.model],
            [.configuration, .sound, .performance],
        ]
    }

    /// Left-to-right order matching the folder tabs (for ←/→).
    static var tabOrder: [SettingsPage] { tabGroups.flatMap { $0 } }

    var keyboardDigit: KeyEquivalent {
        switch self {
        case .home: return "1"
        case .history: return "2"
        case .recording: return "3"
        case .model: return "4"
        case .configuration: return "5"
        case .sound: return "6"
        case .performance: return "7"
        }
    }
}
