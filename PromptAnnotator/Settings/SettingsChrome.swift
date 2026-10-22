import SwiftUI

enum SettingsPage: String, CaseIterable, Identifiable, Hashable {
    case home
    case history
    case recording
    case configuration
    case sound
    case model
    case performance

    var id: String { rawValue }

    var title: String {
        switch self {
        case .home: return "Home"
        case .history: return "History"
        case .recording: return "Recording"
        // Shorter tile label so Departure Mono breathes inside the square.
        case .configuration: return "General"
        case .sound: return "Sound"
        case .model: return "Models"
        case .performance: return "Perf"
        }
    }

    /// Full page heading (may differ from the compact sidebar tile).
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
        case .history: return "clock"
        case .recording: return "record.circle"
        case .configuration: return "gearshape"
        case .sound: return "speaker.wave.2"
        case .model: return "waveform"
        case .performance: return "memorychip"
        }
    }

    static var sidebarSections: [(title: String, pages: [SettingsPage])] {
        [
            ("Session", [.home, .history, .recording]),
            ("Speech", [.model]),
            ("App", [.configuration, .sound, .performance]),
        ]
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
    static let sidebarFooterPadding: CGFloat = Ink.space4
    static let sidebarWidth: CGFloat = Ink.sidebarWidth
}

struct SettingsPageStack<Content: View>: View {
    var title: String
    var subtitle: String? = nil
    @ViewBuilder var content: () -> Content

    var body: some View {
        DTScrollView {
            VStack(alignment: .leading, spacing: Ink.sectionGap) {
                VStack(alignment: .leading, spacing: Ink.titleDescGap) {
                    Text(title)
                        .font(Ink.pageTitleFont)
                        .foregroundStyle(Ink.label)
                    if let subtitle {
                        Text(subtitle)
                            .font(Ink.bodyFont)
                            .foregroundStyle(Ink.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                content()
            }
            .padding(.top, Ink.pageTop)
            .padding(.horizontal, Ink.pageSide)
            .padding(.bottom, Ink.pageBottom)
            .frame(maxWidth: Ink.maxContentWidth, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .inkPageChrome()
    }
}

struct SettingsSection<Content: View>: View {
    var title: String? = nil
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
                InkSectionHeader(title: title)
            }
            content()
            if let footer {
                Text(footer)
                    .font(Ink.captionFont)
                    .foregroundStyle(Ink.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, Ink.space1)
            }
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
                    .strokeBorder(Ink.label, lineWidth: 1)
            )
    }
}

/// B/W segmented control for System / Light / Dark.
struct InkAppearanceSegment: View {
    @Binding var selection: AppAppearance
    var onChange: (AppAppearance) -> Void

    var body: some View {
        HStack(spacing: 0) {
            ForEach(AppAppearance.allCases) { mode in
                let selected = selection == mode
                Button {
                    selection = mode
                    onChange(mode)
                } label: {
                    Text(mode.title.uppercased())
                        .font(Ink.buttonSmallFont)
                        .foregroundStyle(selected ? Ink.onAccent : Ink.label)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, Ink.space2)
                        .background(selected ? Ink.label : Color.clear)
                }
                .buttonStyle(.plain)
                if mode != AppAppearance.allCases.last {
                    Rectangle()
                        .fill(Ink.label)
                        .frame(width: 1)
                }
            }
        }
        .overlay(
            Rectangle()
                .strokeBorder(Ink.label, lineWidth: 1)
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Appearance")
    }
}
