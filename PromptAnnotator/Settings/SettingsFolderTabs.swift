import SwiftUI

/// Chrome-style folder tabs across the top of Settings.
///
/// Selected tab: convex top corners (~6pt) + concave cove feet (fillet into the
/// shelf — not a bullnose ledge). Unselected: rounded tops, straight sides to
/// the baseline (no feet). The shelf rule and selected outline are one continuous
/// 1pt stroke in the selected accent, edge to edge.
struct SettingsFolderTabs: View {
    @Binding var selection: SettingsPage
    var onSearch: (() -> Void)? = nil

    private var tabHeight: CGFloat { Ink.folderTabHeight }
    private var shelfHeight: CGFloat { Ink.space2 + tabHeight }
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
                        Color.clear
                            .frame(width: 2, height: 1)
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
                // Full-width continuous accent path (left edge → tab → right edge).
                SelectedTabShelfStroke(gap: selectedFrame)
                    .stroke(selection.tabAccent, lineWidth: 1)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
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
            // Selected needs side room for outward feet; unselected is flush.
            .padding(.horizontal, selected ? FolderTabShape.foot : 0)
            .frame(height: tabHeight)
            .background {
                FolderTabShape(flared: selected)
                    .fill(selected ? Ink.front : Ink.fill)
            }
            .overlay {
                // Unselected: muted accent outline. Selected outline is the shelf stroke.
                if !selected {
                    FolderTabShape(flared: false)
                        .stroke(page.tabAccent.opacity(0.55), lineWidth: 1)
                }
            }
            // No inner accent stripes — outline carries the color.
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

/// Full-width rule joined to the selected tab’s open outline (outward feet).
/// Pixel-centered on the shelf baseline so joints stay sharp at 1× / 2×.
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
        FolderTabShape.appendFlaredOutline(to: &path, in: tab, shelfY: y, moveToStart: false)
        path.addLine(to: CGPoint(x: rect.maxX, y: y))
        return path
    }
}

// MARK: - Chrome-style tab silhouette

/// Chrome tab geometry.
/// - `flared`: selected — concave cove feet (fillet into shelf) + rounded top.
/// - not flared: unselected — rounded top, straight sides to the baseline (no feet).
struct FolderTabShape: Shape {
    static let corner: CGFloat = 6
    static let foot: CGFloat = 6
    /// Cubic kappa for a quarter-circle Bézier (top corners only).
    private static let k: CGFloat = 0.5522847498

    var flared: Bool

    func path(in rect: CGRect) -> Path {
        var path = Path()
        if flared {
            Self.appendFlaredOutline(to: &path, in: rect, shelfY: rect.maxY, moveToStart: true)
        } else {
            Self.appendPlainOutline(to: &path, in: rect, closeBottom: true)
        }
        return path
    }

    /// Unselected: rounded top, vertical sides, closed on the shelf.
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
    /// Left foot: baseline tip `(sideX - r, shelfY)` → vertical `(sideX, shelfY - r)`.
    /// Arc center is **outside** the tab and **above** the baseline at
    /// `(sideX - r, shelfY - r)`; quad control `(sideX, shelfY)` gives the cove.
    /// The side then rises straight from the fillet end — no ledge or extra step.
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

        // Left concave fillet: tangent to baseline at tip, tangent to side at (sideLeft, shelfY - f).
        path.addQuadCurve(
            to: CGPoint(x: sideLeft, y: shelfY - f),
            control: CGPoint(x: sideLeft, y: shelfY)
        )

        // Straight side — fillet already ends on the wall.
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

        // Right concave fillet (mirrored).
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: shelfY),
            control: CGPoint(x: sideRight, y: shelfY)
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
