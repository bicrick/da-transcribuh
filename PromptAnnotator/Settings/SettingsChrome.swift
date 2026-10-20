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
        case .model: return "Model"
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
}

struct SettingsPageStack<Content: View>: View {
    var title: String
    @ViewBuilder var content: () -> Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text(title)
                    .font(.system(size: 22, weight: .semibold))
                content()
            }
            .padding(28)
            .frame(maxWidth: 680, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(nsColor: .windowBackgroundColor))
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
            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color(nsColor: .separatorColor).opacity(0.7), lineWidth: 1)
        )
    }
}

struct SettingsDivider: View {
    var body: some View {
        Rectangle()
            .fill(Color(nsColor: .separatorColor).opacity(0.7))
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
