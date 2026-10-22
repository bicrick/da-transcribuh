import SwiftUI

/// Chrome-style folder tabs across the top of Settings.
///
/// Layout is **selection-invariant** (Chrome): every tab keeps the same frame
/// whether selected or not. Feet are paint-only overlays that extend outside the
/// layout box. The selected-accent shelf + selected outline are one continuous
/// `Ink.stroke` path, edge to edge, drawn above unselected bottoms.
struct SettingsFolderTabs: View {
    @Binding var selection: SettingsPage
    var onSearch: (() -> Void)? = nil

    private var tabHeight: CGFloat { Ink.folderTabHeight }
    private var shelfHeight: CGFloat { Ink.space2 + tabHeight }
    /// Seal selected fill into the page under the 2pt shelf stroke.
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
                    .frame(height: tabHeight, alignment: .center)
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
                // Full-width continuous accent path — drawn last so it sits on top of
                // unselected tab bottoms across the entire window width.
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
            // Fixed label metrics — same padding / font whether selected or not.
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
                // Fill stays inside the layout box for both states (no foot padding).
                FolderTabShape(flared: false)
                    .fill(selected ? Ink.front : Ink.fill)
            }
            .overlay {
                // Unselected: open-bottom outline (sides terminate on the shelf).
                // Selected outline is the continuous shelf stroke.
                if !selected {
                    FolderTabShape(flared: false, closeBottom: false)
                        .stroke(page.tabAccent.opacity(0.55), lineWidth: Ink.stroke)
                }
            }
            .background(alignment: .bottom) {
                // Selected fill bleed under the shelf stroke — does not change layout height.
                if selected {
                    Ink.front
                        .frame(height: selectedBleed)
                        .offset(y: selectedBleed)
                }
            }
            .background {
                // Report the layout frame; shelf stroke expands feet outside this box.
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
        // Feet / shelf paint above neighbors; layout frames stay put.
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
    /// Gap between tabs inside a group (selection-invariant).
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

/// Full-width rule joined to the selected tab’s open outline (concave feet).
/// Feet extend `FolderTabShape.foot` outside the reported layout frame so
/// selection never changes tab width. Pixel-centered for `Ink.stroke` at 1× / 2×.
private struct SelectedTabShelfStroke: Shape {
    var gap: CGRect

    func path(in rect: CGRect) -> Path {
        let stroke = Ink.stroke
        let y = rect.maxY - stroke / 2
        var path = Path()

        let foot = FolderTabShape.foot
        if gap.isNull || gap.isEmpty || gap.width <= 1 {
            path.move(to: CGPoint(x: rect.minX, y: y))
            path.addLine(to: CGPoint(x: rect.maxX, y: y))
            return path
        }

        // Layout frame is the label box; flared outline lives in an expanded rect.
        let tab = CGRect(
            x: gap.minX - foot,
            y: gap.minY,
            width: gap.width + 2 * foot,
            height: max(0, y + stroke / 2 - gap.minY)
        )
        path.move(to: CGPoint(x: rect.minX, y: y))
        path.addLine(to: CGPoint(x: tab.minX, y: y))
        FolderTabShape.appendFlaredOutline(to: &path, in: tab, shelfY: y, moveToStart: false)
        path.addLine(to: CGPoint(x: rect.maxX, y: y))
        return path
    }
}

// MARK: - Chrome-style tab silhouette

/// Chrome tab geometry.
/// - `flared`: selected shelf path — concave cove feet outside the layout box.
/// - not flared: rounded top; `closeBottom` false for unselected outlines (no bottom edge).
struct FolderTabShape: Shape {
    static let corner: CGFloat = 6
    /// Cove fillet radius; sized for `Ink.stroke` (2pt) so joints stay clean.
    static let foot: CGFloat = 8
    /// Cubic kappa for a quarter-circle Bézier (top corners only).
    private static let k: CGFloat = 0.5522847498

    var flared: Bool
    var closeBottom: Bool = true

    func path(in rect: CGRect) -> Path {
        var path = Path()
        if flared {
            Self.appendFlaredOutline(to: &path, in: rect, shelfY: rect.maxY, moveToStart: true)
        } else {
            Self.appendPlainOutline(to: &path, in: rect, closeBottom: closeBottom)
        }
        return path
    }

    /// Unselected / fill: rounded top, vertical sides. Open bottom when used as an
    /// outline so the continuous accent shelf shows through underneath.
    static func appendPlainOutline(to path: inout Path, in rect: CGRect, closeBottom: Bool) {
        let r = min(corner, rect.width / 2, rect.height / 2)
        let kappa = k * r
        path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + r))
        path.addCurve(
            to: CGPoint(x: rect.minX + r, y: rect.minY),
            control1: CGPoint(x: rect.minX, y: rect.minY + r - kappa),
            control2: CGPoint(x: rect.minX + r - kappa, y: rect.minY)
        )
        path.addLine(to: CGPoint(x: rect.maxX - r, y: rect.minY))
        path.addCurve(
            to: CGPoint(x: rect.maxX, y: rect.minY + r),
            control1: CGPoint(x: rect.maxX - r + kappa, y: rect.minY),
            control2: CGPoint(x: rect.maxX, y: rect.minY + r - kappa)
        )
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        if closeBottom {
            path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
            path.closeSubpath()
        }
    }

    /// Selected open outline with Chrome **concave** feet (cove / fillet, not bullnose).
    ///
    /// `rect` is the flared paint box (layout frame expanded by `foot` on each side).
    /// Left foot: baseline tip `(sideX - r, shelfY)` → vertical `(sideX, shelfY - r)`.
    /// Quad control `(sideX, shelfY)` — arc center outside the tab above the baseline.
    static func appendFlaredOutline(
        to path: inout Path,
        in rect: CGRect,
        shelfY: CGFloat,
        moveToStart: Bool
    ) {
        let f = foot
        let r = min(corner, max(0, (rect.width - 2 * f) / 2), max(0, (shelfY - rect.minY) / 2))
        let sideLeft = rect.minX + f
        let sideRight = rect.maxX - f
        let top = rect.minY
        let kappaR = k * r

        if moveToStart {
            path.move(to: CGPoint(x: rect.minX, y: shelfY))
        }

        path.addQuadCurve(
            to: CGPoint(x: sideLeft, y: shelfY - f),
            control: CGPoint(x: sideLeft, y: shelfY)
        )

        path.addLine(to: CGPoint(x: sideLeft, y: top + r))

        path.addCurve(
            to: CGPoint(x: sideLeft + r, y: top),
            control1: CGPoint(x: sideLeft, y: top + r - kappaR),
            control2: CGPoint(x: sideLeft + r - kappaR, y: top)
        )

        path.addLine(to: CGPoint(x: sideRight - r, y: top))

        path.addCurve(
            to: CGPoint(x: sideRight, y: top + r),
            control1: CGPoint(x: sideRight - r + kappaR, y: top),
            control2: CGPoint(x: sideRight, y: top + r - kappaR)
        )

        path.addLine(to: CGPoint(x: sideRight, y: shelfY - f))

        path.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: shelfY),
            control: CGPoint(x: sideRight, y: shelfY)
        )
    }

    /// Ideal layout size for a tab label (selection-invariant).
    static func layoutSize(titleWidth: CGFloat, height: CGFloat = Ink.folderTabHeight) -> CGSize {
        // icon (~10) + gap (5) + title + horizontal pad × 2
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
