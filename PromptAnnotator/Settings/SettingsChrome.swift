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
        case .configuration: return "Configuration"
        case .sound: return "Sound"
        case .model: return "Models"
        case .performance: return "Performance"
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

    /// Sidebar grouping for a clearer native Settings layout.
    static var sidebarSections: [(title: String, pages: [SettingsPage])] {
        [
            ("Session", [.home, .history, .recording]),
            ("Speech", [.model]),
            ("App", [.configuration, .sound, .performance]),
        ]
    }
}

/// Shared metrics so Settings pages share spacing, width, and card chrome.
enum SettingsMetrics {
    static let pagePadding: CGFloat = 24
    static let pageSpacing: CGFloat = 20
    static let sectionSpacing: CGFloat = 8
    static let rowPadding: CGFloat = 12
    static let maxContentWidth: CGFloat = 640
    static let cardCorner: CGFloat = 10
    static let sidebarFooterPadding: CGFloat = 12
}

struct SettingsPageStack<Content: View>: View {
    var title: String
    @ViewBuilder var content: () -> Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SettingsMetrics.pageSpacing) {
                Text(title)
                    .font(.system(size: 22, weight: .semibold))
                content()
            }
            .padding(SettingsMetrics.pagePadding)
            .frame(maxWidth: SettingsMetrics.maxContentWidth, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

/// Section title + content with consistent spacing (Form-like grouping without a full Form rewrite).
struct SettingsSection<Content: View>: View {
    var title: String?
    var footer: String?
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
        VStack(alignment: .leading, spacing: SettingsMetrics.sectionSpacing) {
            if let title {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                    .tracking(0.3)
            }
            content()
            if let footer {
                Text(footer)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

struct SettingsCard<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            Color(nsColor: .controlBackgroundColor),
            in: RoundedRectangle(cornerRadius: SettingsMetrics.cardCorner, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: SettingsMetrics.cardCorner, style: .continuous)
                .strokeBorder(Color(nsColor: .separatorColor).opacity(0.55), lineWidth: 1)
        )
    }
}

struct SettingsDivider: View {
    var body: some View {
        Rectangle()
            .fill(Color(nsColor: .separatorColor).opacity(0.55))
            .frame(height: 1)
            .padding(.leading, 46)
    }
}

struct ShortcutBadge: View {
    var text: String

    var body: some View {
        Text(text)
            .font(.system(size: 12, weight: .medium))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(
                Color(nsColor: .quaternaryLabelColor).opacity(0.18),
                in: RoundedRectangle(cornerRadius: 6, style: .continuous)
            )
    }
}
