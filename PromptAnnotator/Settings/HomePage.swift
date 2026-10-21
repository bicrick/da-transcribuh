import AppKit
import SwiftUI

struct HomePage: View {
    @ObservedObject var session: SessionController
    @ObservedObject var settings: AppSettings
    @ObservedObject var permissions: PermissionModel
    var sessions: [SessionSummary]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header
                stats
                Text("Get started")
                    .font(.system(size: 15, weight: .semibold))
                SettingsCard {
                    startRow
                    SettingsDivider()
                    permissionRow
                    if sessions.isEmpty {
                        SettingsDivider()
                        firstSessionRow
                    }
                    SettingsDivider()
                    drawRow
                    SettingsDivider()
                    folderRow
                }
            }
            .padding(28)
            .frame(maxWidth: 720, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear { permissions.refresh() }
    }

    private var header: some View {
        HStack(spacing: 16) {
            AppLogo(side: 64)
            VStack(alignment: .leading, spacing: 3) {
                Text("Mutter")
                    .font(.system(size: 22, weight: .semibold))
                Text(AppVersion.label)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                Text("Dictation in the menu bar. Capture the screen when you want the picture with the words.")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var stats: some View {
        let numbers = SessionLibrary.stats(from: sessions)
        return SettingsCard {
            HStack(spacing: 0) {
                stat(value: numbers.sessions, label: numbers.sessions == 1 ? "Session" : "Sessions")
                stat(value: numbers.tiles, label: numbers.tiles == 1 ? "Tile" : "Tiles")
                stat(value: numbers.words, label: numbers.words == 1 ? "Word" : "Words")
                stat(value: numbers.minutes, label: numbers.minutes == 1 ? "Minute" : "Minutes")
            }
            .padding(.vertical, 16)
        }
    }

    private func stat(value: Int, label: String) -> some View {
        VStack(spacing: 4) {
            Text("\(value)")
                .font(.system(size: 22, weight: .semibold))
                .monospacedDigit()
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private var startRow: some View {
        HStack(spacing: 12) {
            rowIcon(startRowSymbol)
            VStack(alignment: .leading, spacing: 2) {
                Text(startRowTitle)
                    .font(.system(size: 13, weight: .semibold))
                Text(startRowDetail)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            ShortcutBadge(text: settings.chord.display)
            Button(session.phase == .recording ? "Stop" : "Start") {
                session.toggle()
            }
            .disabled(session.isBusy)
            .accessibilityLabel(session.phase == .recording ? "Stop session" : "Start session")
            .accessibilityHint("Shortcut \(settings.chord.display)")
        }
        .padding(12)
        .accessibilityElement(children: .contain)
    }

    private var startRowSymbol: String {
        switch session.phase {
        case .recording:
            return "record.circle.fill"
        case .finishing, .downloading, .preparingModel, .transcribing:
            return "ellipsis.circle"
        case .idle:
            return "record.circle"
        }
    }

    private var startRowTitle: String {
        let live = session.statusText
        if !live.isEmpty { return live }
        return "Start a session"
    }

    private var startRowDetail: String {
        if session.isBusy {
            return "Mutter is finishing this take. The menu bar icon shows the same state."
        }
        if settings.pushToTalk {
            return "Hold \(settings.chord.display) to talk. Release to stop. The Start button stays a tap."
        }
        if sessions.isEmpty {
            return "First take: \(settings.chord.display) starts and stops. Words land on the clipboard."
        }
        return "\(settings.chord.display) starts. The same shortcut stops."
    }

    private var permissionRow: some View {
        HStack(spacing: 12) {
            rowIcon(permissions.status.isReady ? "checkmark.circle" : "lock")
            VStack(alignment: .leading, spacing: 2) {
                Text("Permissions")
                    .font(.system(size: 13, weight: .semibold))
                Text(permissionDetail)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            if !permissions.status.isReady {
                Button("Turn On") {
                    Task {
                        _ = await Permissions.requestMicrophone()
                        Permissions.revealSettings(for: Permissions.current())
                        permissions.refresh()
                    }
                }
                .accessibilityHint("Opens System Settings for the permissions Mutter still needs")
                Button("Reopen") {
                    Permissions.relaunch()
                }
                .accessibilityHint("Quits and relaunches Mutter after you change permissions")
            }
        }
        .padding(12)
    }

    private var firstSessionRow: some View {
        HStack(spacing: 12) {
            rowIcon("mic")
            VStack(alignment: .leading, spacing: 2) {
                Text("No sessions yet")
                    .font(.system(size: 13, weight: .semibold))
                Text(firstSessionDetail)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
    }

    private var firstSessionDetail: String {
        if !permissions.status.isReady {
            return "Turn on permissions above, then press Start or \(settings.chord.display)."
        }
        if WhisperModelLocator.locate(
            in: WhisperKitTranscriber.modelsFolder(),
            variant: settings.speechModel
        ) == nil {
            return "Download a speech model on the Model page, then press Start or \(settings.chord.display)."
        }
        return "Press Start or \(settings.chord.display), speak, then stop. History fills in after your first take."
    }

    private var permissionDetail: String {
        if let missing = permissions.status.summary {
            return "Turn on \(missing). If a switch is already on, turn it off and on, then reopen."
        }
        return "Screen Recording, Microphone, and Accessibility are on."
    }

    private var drawRow: some View {
        HStack(spacing: 12) {
            rowIcon("viewfinder")
            VStack(alignment: .leading, spacing: 2) {
                Text("Talk, or drag to capture")
                    .font(.system(size: 13, weight: .semibold))
                Text("Hold Shift to mark the screen, then drag. Speech alone pastes the transcript. A capture pastes the picture with the words.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
    }

    private var folderRow: some View {
        HStack(spacing: 12) {
            rowIcon("folder")
            VStack(alignment: .leading, spacing: 2) {
                Text("Sessions folder")
                    .font(.system(size: 13, weight: .semibold))
                Text(SessionStore.displayPath())
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Button("Show") {
                if let root = try? SessionPaths.sessionsRoot() {
                    NSWorkspace.shared.open(root)
                }
            }
        }
        .padding(12)
    }

    private func rowIcon(_ name: String) -> some View {
        Image(systemName: name)
            .font(.system(size: 15, weight: .medium))
            .frame(width: 22)
            .foregroundStyle(.primary)
    }
}

@MainActor
final class PermissionModel: ObservableObject {
    @Published private(set) var status = Permissions.current()

    func refresh() {
        status = Permissions.current()
    }
}
