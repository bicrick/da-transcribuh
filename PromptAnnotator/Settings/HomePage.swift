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
                Text("Prompt Annotator")
                    .font(.system(size: 22, weight: .semibold))
                Text("Mark the screen while you talk. Each Shift-hold becomes a tile.")
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
            rowIcon("record.circle")
            VStack(alignment: .leading, spacing: 2) {
                Text(session.phase == .recording ? "Session in progress" : "Start a session")
                    .font(.system(size: 13, weight: .semibold))
                Text("A tap starts. A second tap stops.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            ShortcutBadge(text: settings.chord.display)
            Button(session.phase == .recording ? "Stop" : "Start") {
                session.toggle()
            }
            .disabled(session.isBusy)
        }
        .padding(12)
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
                    Permissions.revealSettings(for: permissions.status)
                }
                Button("Reopen") {
                    Permissions.relaunch()
                }
            }
        }
        .padding(12)
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
                Text("Drag to capture a snippet")
                    .font(.system(size: 13, weight: .semibold))
                Text("A click or scroll still reaches the page. Pick a draw tool, then hold Shift to mark.")
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
                Text("Documents / PromptAnnotator / Sessions")
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
