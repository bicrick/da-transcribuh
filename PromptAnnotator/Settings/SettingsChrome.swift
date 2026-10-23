import SwiftUI

enum SettingsPage: String, CaseIterable, Identifiable, Hashable {
    case home
    case appearance
    case history
    case clipboard
    case configuration
    case sound
    case model
    case performance

    var id: String { rawValue }

    var title: String {
        switch self {
        case .home: return "Home"
        case .appearance: return "Appearance"
        case .history: return "History"
        case .clipboard: return "Clipboard"
        // Compact folder-tab label.
        case .configuration: return "General"
        case .sound: return "Sound"
        case .model: return "Models"
        case .performance: return "Perf"
        }
    }

    /// Full page heading (may differ from the compact folder-tab label).
    var pageTitle: String {
        switch self {
        case .configuration: return "General"
        case .performance: return "Performance"
        default: return title
        }
    }

    var symbol: String {
        switch self {
        case .home: return "house"
        case .appearance: return "paintpalette"
        case .history: return "clock"
        case .clipboard: return "doc.on.clipboard"
        case .configuration: return "gearshape"
        case .sound: return "speaker.wave.2"
        case .model: return "waveform"
        case .performance: return "memorychip"
        }
    }

}

/// Layout metrics — Ink tokens, kept under the SettingsMetrics name for call sites.
enum SettingsMetrics {
    static let pagePadding: CGFloat = Ink.pageSide
    static let pageTop: CGFloat = Ink.pageTop
    static let pageSpacing: CGFloat = Ink.sectionGap
    static let sectionSpacing: CGFloat = Ink.sectionInnerGap
    static let rowPadding: CGFloat = Ink.rowHPad
    static let maxContentWidth: CGFloat = Ink.maxContentWidth
    static let cardCorner: CGFloat = Ink.cardRadius
    static let folderTabHeight: CGFloat = Ink.folderTabHeight
}

/// Compact page title + optional one-line caption — same language as Home.
struct InkPageHeader: View {
    var title: String
    var subtitle: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: Ink.titleDescGap) {
            Text(title)
                .font(Ink.pageTitleFont)
                .foregroundStyle(Ink.label)
                .fixedSize(horizontal: false, vertical: true)
            if let subtitle {
                Text(subtitle)
                    .font(Ink.bodyFont)
                    .foregroundStyle(Ink.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

struct SettingsPageStack<Content: View>: View {
    var title: String
    var subtitle: String? = nil
    @ViewBuilder var content: () -> Content

    var body: some View {
        DTScrollView {
            VStack(alignment: .leading, spacing: Ink.sectionGap) {
                InkPageHeader(title: title, subtitle: subtitle)
                content()
            }
            .inkPageColumn()
        }
        .inkPageChrome()
    }
}

extension View {
    /// The one page column every Settings page and onboarding step uses: pageTop,
    /// pageSide and pageBottom padding, capped at maxContentWidth, centred.
    ///
    /// Inside a DTScrollView the column is centred in the area left of the
    /// scroller gutter. A page that does not scroll as a whole (History's log)
    /// passes `reservesScrollerGutter` so its column lands on the same x as the
    /// scrolling pages instead of half a gutter to the right (measured +7pt).
    /// `fillsHeight` is for pages whose content takes the window's height.
    func inkPageColumn(fillsHeight: Bool = false, reservesScrollerGutter: Bool = false) -> some View {
        self
            .padding(.top, Ink.pageTop)
            .padding(.horizontal, Ink.pageSide)
            .padding(.bottom, Ink.pageBottom)
            .frame(maxWidth: Ink.maxContentWidth, maxHeight: fillsHeight ? .infinity : nil, alignment: .topLeading)
            .padding(.trailing, reservesScrollerGutter ? Ink.scrollerGutter : 0)
            // minHeight 0 keeps a fill-height page from turning its squeezed
            // height into the window's minimum (see HistoryPage).
            .frame(
                minWidth: 0,
                maxWidth: .infinity,
                minHeight: fillsHeight ? 0 : nil,
                maxHeight: fillsHeight ? .infinity : nil,
                alignment: .top
            )
    }
}

struct SettingsSection<Content: View>: View {
    var title: String? = nil
    /// One short caption under the section header (flush to the grid).
    var footer: String? = nil
    @ViewBuilder var content: () -> Content

    init(
        title: String? = nil,
        footer: String? = nil,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.title = title
        self.footer = footer
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Ink.sectionInnerGap) {
            if let title {
                InkSectionHeader(title: title, caption: footer)
            } else if let footer {
                Text(footer)
                    .font(Ink.captionFont)
                    .foregroundStyle(Ink.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            content()
        }
    }
}

struct SettingsCard<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        InkCard { content() }
    }
}

struct SettingsDivider: View {
    var body: some View {
        InkDivider(leading: 46)
    }
}

struct ShortcutBadge: View {
    var text: String

    var body: some View {
        Text(text)
            .font(Ink.badgeFont)
            .foregroundStyle(Ink.label)
            .padding(.horizontal, Ink.space2)
            .padding(.vertical, Ink.space1)
            .overlay(
                RoundedRectangle(cornerRadius: Ink.buttonRadius, style: .continuous)
                    .strokeBorder(Ink.label, lineWidth: Ink.stroke)
            )
    }
}

/// B/W segmented control for System / Light / Dark.
/// Writes only through `selection` — callers must not also fire a second onChange
/// (that double-called `setAppearance` and re-applied `NSApp.appearance` every click).
struct InkAppearanceSegment: View {
    @Binding var selection: AppAppearance

    var body: some View {
        HStack(spacing: 0) {
            ForEach(AppAppearance.allCases) { mode in
                let selected = selection == mode
                Button {
                    selection = mode
                } label: {
                    Text(mode.title.uppercased())
                        .font(Ink.buttonSmallFont)
                        .foregroundStyle(selected ? Ink.onPrimary : Ink.label)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, Ink.space2)
                        .contentShape(Rectangle())
                        .background(selected ? Ink.primaryFill : Color.clear)
                }
                .buttonStyle(.plain)
                if mode != AppAppearance.allCases.last {
                    Rectangle()
                        .fill(Ink.controlBorder)
                        .frame(width: 1)
                }
            }
        }
        .overlay(
            Rectangle()
                .strokeBorder(Ink.controlBorder, lineWidth: Ink.stroke)
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Appearance")
    }
}
