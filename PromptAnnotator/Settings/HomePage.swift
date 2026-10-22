import AppKit
import SwiftUI

struct HomePage: View {
    @ObservedObject var session: SessionController
    @ObservedObject var settings: AppSettings
    @ObservedObject var permissions: PermissionModel
    var sessions: [SessionSummary]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                hero
                stats
                SettingsSection(title: "Get started") {
                    checklist
                }
                tips
            }
            .padding(.top, Ink.pageTop)
            .padding(.horizontal, Ink.pageSide)
            .padding(.bottom, Ink.pageBottom)
            .frame(maxWidth: Ink.maxContentWidth, alignment: .leading)
        }
        .inkPageChrome()
        .onAppear { permissions.refresh() }
    }

    private var hero: some View {
        InkCard {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .top, spacing: 16) {
                    AppLogo(side: 56)
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 8) {
                            Text("Mutter")
                                .font(.system(size: 24, weight: .bold))
                                .foregroundStyle(Ink.label)
                            InkBadge(text: AppVersion.label)
                        }
                        Text("Dictation in the menu bar. Capture the screen when you want the picture with the words.")
                            .font(Ink.bodyFont)
                            .foregroundStyle(Ink.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.horizontal, 22)
                .padding(.top, 22)

                InkDivider(leading: 0)

                HStack(alignment: .center, spacing: 16) {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 8) {
                            statusDot
                            Text(startRowTitle)
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(Ink.label)
                        }
                        Text(startRowDetail)
                            .font(Ink.captionFont)
                            .foregroundStyle(Ink.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 8)
                    InkKeycapRow(keys: settings.chord.keycaps)
                    Button {
                        session.toggle()
                    } label: {
                        Label(
                            session.phase == .recording ? "Stop" : "Start",
                            systemImage: session.phase == .recording ? "stop.circle.fill" : "record.circle"
                        )
                    }
                    .buttonStyle(InkPrimaryButtonStyle(large: true, enabled: !session.isBusy))
                    .disabled(session.isBusy)
                    .accessibilityLabel(session.phase == .recording ? "Stop session" : "Start session")
                    .accessibilityHint("Shortcut \(settings.chord.display)")
                }
                .padding(.horizontal, 22)
                .padding(.bottom, 20)
            }
            .background(
                LinearGradient(
                    colors: [Ink.accentSoft, Color.clear],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
        }
    }

    private var statusDot: some View {
        Circle()
            .fill(session.isBusy || session.phase == .recording ? Ink.accent : Ink.success)
            .frame(width: 8, height: 8)
            .overlay(
                Circle()
                    .stroke(Ink.success.opacity(0.25), lineWidth: 3)
                    .opacity(session.phase == .idle && !session.isBusy ? 1 : 0)
            )
    }

    private var stats: some View {
        let numbers = SessionLibrary.stats(from: sessions)
        return LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: Ink.gridGap), count: 4),
            spacing: Ink.gridGap
        ) {
            statTile(icon: "mic", value: numbers.sessions, label: numbers.sessions == 1 ? "Session" : "Sessions")
            statTile(icon: "photo", value: numbers.tiles, label: numbers.tiles == 1 ? "Tile" : "Tiles")
            statTile(icon: "text.alignleft", value: numbers.words, label: numbers.words == 1 ? "Word" : "Words")
            statTile(icon: "timer", value: numbers.minutes, label: numbers.minutes == 1 ? "Minute" : "Minutes")
        }
    }

    private func statTile(icon: String, value: Int, label: String) -> some View {
        InkTile {
            VStack(alignment: .leading, spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Ink.accent)
                Text("\(value)")
                    .font(Ink.statValueFont)
                    .monospacedDigit()
                    .foregroundStyle(Ink.label)
                Text(label)
                    .font(Ink.captionFont)
                    .foregroundStyle(Ink.secondary)
            }
        }
    }

    private var checklist: some View {
        let items = checklistItems
        let done = items.filter(\.done).count
        return InkCard {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 12) {
                    Text("\(done) of \(items.count) done")
                        .font(Ink.rowTitleFont)
                        .foregroundStyle(Ink.label)
                    InkProgressBar(fraction: items.isEmpty ? 0 : Double(done) / Double(items.count))
                }
                .padding(.horizontal, Ink.rowHPad)
                .padding(.vertical, 14)

                ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                    InkDivider(leading: Ink.rowHPad)
                    HStack(alignment: .top, spacing: 12) {
                        InkCheck(done: item.done)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.title)
                                .font(Ink.rowTitleFont)
                                .foregroundStyle(Ink.label)
                            Text(item.detail)
                                .font(Ink.captionFont)
                                .foregroundStyle(Ink.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 0)
                        if let trail = item.trail {
                            trail
                        }
                    }
                    .padding(.horizontal, Ink.rowHPad)
                    .padding(.vertical, 12)
                }
            }
        }
    }

    private var tips: some View {
        InkCard {
            VStack(alignment: .leading, spacing: 0) {
                tipRow(
                    icon: "viewfinder",
                    title: "Talk, or drag to capture",
                    detail: "Hold Shift to mark the screen, then drag. Speech alone pastes the transcript. A capture pastes the picture with the words.",
                    trailing: nil
                )
                InkDivider(leading: 58)
                tipRow(
                    icon: "folder",
                    title: "Sessions folder",
                    detail: SessionStore.displayPath(),
                    trailing: AnyView(
                        Button("Show") {
                            if let root = try? SessionPaths.sessionsRoot() {
                                NSWorkspace.shared.open(root)
                            }
                        }
                        .buttonStyle(InkSecondaryButtonStyle())
                    )
                )
            }
        }
    }

    private func tipRow(icon: String, title: String, detail: String, trailing: AnyView?) -> some View {
        HStack(alignment: .center, spacing: 12) {
            InkIconChip(systemName: icon)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(Ink.rowTitleFont)
                    .foregroundStyle(Ink.label)
                Text(detail)
                    .font(Ink.captionFont)
                    .foregroundStyle(Ink.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            if let trailing {
                trailing
            }
        }
        .padding(.horizontal, Ink.rowHPad)
        .padding(.vertical, 14)
    }

    private struct ChecklistItem {
        var done: Bool
        var title: String
        var detail: String
        var trail: AnyView?
    }

    private var checklistItems: [ChecklistItem] {
        var items: [ChecklistItem] = [
            ChecklistItem(
                done: permissions.status.isReady,
                title: "Permissions",
                detail: permissionDetail,
                trail: permissions.status.isReady ? nil : AnyView(
                    HStack(spacing: 6) {
                        Button("Turn On") {
                            Task {
                                _ = await Permissions.requestMicrophone()
                                Permissions.revealSettings(for: Permissions.current())
                                permissions.refresh()
                            }
                        }
                        .buttonStyle(InkSecondaryButtonStyle())
                        Button("Reopen") { Permissions.relaunch() }
                            .buttonStyle(InkSecondaryButtonStyle())
                    }
                )
            ),
            ChecklistItem(
                done: modelReady,
                title: "Speech model",
                detail: modelDetail,
                trail: nil
            ),
            ChecklistItem(
                done: !sessions.isEmpty,
                title: sessions.isEmpty ? "First take" : "First take",
                detail: sessions.isEmpty
                    ? firstSessionDetail
                    : "\(sessions.count) session\(sessions.count == 1 ? "" : "s") in History.",
                trail: nil
            ),
        ]
        return items
    }

    private var modelReady: Bool {
        if settings.speechEngine == .openAICompatible {
            return OpenAICompatibleTranscriber.isConfigured()
        }
        return WhisperKitTranscriber.modelIsInstalled()
    }

    private var modelDetail: String {
        if settings.speechEngine == .openAICompatible {
            return OpenAICompatibleTranscriber.isConfigured()
                ? "OpenAI-compatible server is configured."
                : "Add a server API key on the Models page."
        }
        if WhisperKitTranscriber.modelIsInstalled() {
            let choice = SpeechModelChoice.stored(settings.speechModel)
            return "\(choice.title) (\(choice.variant)) is on this Mac."
        }
        return "Download a speech model on the Models page."
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
        return "\(settings.chord.display) starts. The same shortcut stops."
    }

    private var firstSessionDetail: String {
        if !permissions.status.isReady {
            return "Turn on permissions above, then press Start or \(settings.chord.display)."
        }
        if settings.speechEngine == .openAICompatible {
            if !OpenAICompatibleTranscriber.isConfigured() {
                return "Add a server API key on the Models page, then press Start or \(settings.chord.display)."
            }
            return "Press Start or \(settings.chord.display), speak, then stop."
        }
        if !WhisperKitTranscriber.modelIsInstalled() {
            return "Download a speech model on the Models page, then press Start or \(settings.chord.display)."
        }
        return "Press Start or \(settings.chord.display), speak, then stop. History fills in after your first take."
    }

    private var permissionDetail: String {
        if let missing = permissions.status.summary {
            return "Turn on \(missing). If a switch is already on, turn it off and on, then reopen."
        }
        return "Screen Recording, Microphone, and Accessibility are on."
    }
}

@MainActor
final class PermissionModel: ObservableObject {
    @Published private(set) var status = Permissions.current()

    func refresh() {
        status = Permissions.current()
    }
}
