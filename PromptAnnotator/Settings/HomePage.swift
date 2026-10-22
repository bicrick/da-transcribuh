import AppKit
import SwiftUI

struct HomePage: View {
    @ObservedObject var session: SessionController
    @ObservedObject var settings: AppSettings
    @ObservedObject var permissions: PermissionModel
    var sessions: [SessionSummary]

    var body: some View {
        DTScrollView {
            VStack(alignment: .leading, spacing: Ink.sectionGap) {
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
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .inkPageChrome()
        .onAppear { permissions.refresh() }
    }

    private var hero: some View {
        InkCard {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .center, spacing: Ink.space3) {
                    AppLogo(side: 40)
                    VStack(alignment: .leading, spacing: Ink.titleDescGap) {
                        HStack(spacing: Ink.space2) {
                            DTWordmark(size: 16)
                            InkBadge(text: AppVersion.label)
                        }
                        Text("Dictation in the menu bar. Capture the screen when you want the picture with the words.")
                            .font(Ink.bodyFont)
                            .foregroundStyle(Ink.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    Spacer(minLength: 0)
                }
                .padding(Ink.cardPad)

                Rectangle().fill(Ink.label).frame(height: 1)

                HStack(alignment: .center, spacing: Ink.space3) {
                    VStack(alignment: .leading, spacing: Ink.titleDescGap) {
                        HStack(spacing: Ink.space2) {
                            Rectangle()
                                .fill(Ink.label)
                                .frame(width: 8, height: 8)
                            Text(startRowTitle)
                                .font(Ink.labelFont)
                                .foregroundStyle(Ink.label)
                        }
                        Text(startRowDetail)
                            .font(Ink.captionFont)
                            .foregroundStyle(Ink.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    Spacer(minLength: Ink.space2)
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
                .padding(Ink.cardPad)
            }
        }
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
        VStack(alignment: .leading, spacing: Ink.space2) {
            Image(systemName: icon)
                .font(Ink.labelFont)
                .foregroundStyle(Ink.label)
            Text("\(value)")
                .font(Ink.numberFont)
                .monospacedDigit()
                .foregroundStyle(Ink.label)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label.uppercased())
                .font(Ink.headingFont)
                .foregroundStyle(Ink.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, minHeight: 88, alignment: .topLeading)
        .padding(Ink.space3)
        .overlay(
            Rectangle()
                .strokeBorder(Ink.label, lineWidth: 1)
        )
    }

    private var checklist: some View {
        let items = checklistItems
        let done = items.filter(\.done).count
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: Ink.space3) {
                Text("\(done) of \(items.count) done".uppercased())
                    .font(Ink.headingFont)
                    .foregroundStyle(Ink.label)
                InkProgressBar(fraction: items.isEmpty ? 0 : Double(done) / Double(items.count))
            }
            .padding(.horizontal, Ink.rowHPad)
            .padding(.vertical, Ink.space3)
            .overlay(alignment: .bottom) {
                Rectangle().fill(Ink.label).frame(height: 1)
            }

            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                HStack(alignment: .top, spacing: Ink.space3) {
                    InkCheck(done: item.done)
                        .padding(.top, 1)
                    VStack(alignment: .leading, spacing: Ink.titleDescGap) {
                        Text(item.title)
                            .font(Ink.labelFont)
                            .foregroundStyle(Ink.label)
                        Text(item.detail)
                            .font(Ink.captionFont)
                            .foregroundStyle(Ink.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    Spacer(minLength: 0)
                    if let trail = item.trail {
                        trail
                    }
                }
                .padding(.horizontal, Ink.rowHPad)
                .padding(.vertical, Ink.space3)
                .overlay(alignment: .bottom) {
                    Rectangle().fill(Ink.label).frame(height: 1)
                }
            }
        }
        .overlay(
            Rectangle()
                .strokeBorder(Ink.label, lineWidth: 1)
        )
    }

    private var tips: some View {
        VStack(alignment: .leading, spacing: 0) {
            tipRow(
                icon: "viewfinder",
                title: "Talk, or drag to capture",
                detail: "Hold Shift to mark the screen, then drag. Speech alone pastes the transcript. A capture pastes the picture with the words.",
                trailing: nil
            )
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
        .overlay(
            Rectangle()
                .strokeBorder(Ink.label, lineWidth: 1)
        )
    }

    private func tipRow(icon: String, title: String, detail: String, trailing: AnyView?) -> some View {
        HStack(alignment: .center, spacing: Ink.space3) {
            InkIconChip(systemName: icon)
            VStack(alignment: .leading, spacing: Ink.titleDescGap) {
                Text(title)
                    .font(Ink.labelFont)
                    .foregroundStyle(Ink.label)
                Text(detail)
                    .font(Ink.captionFont)
                    .foregroundStyle(Ink.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            Spacer(minLength: Ink.space2)
            if let trailing {
                trailing
            }
        }
        .padding(.horizontal, Ink.rowHPad)
        .padding(.vertical, Ink.space3)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Ink.label).frame(height: 1)
        }
    }

    private struct ChecklistItem {
        var done: Bool
        var title: String
        var detail: String
        var trail: AnyView?
    }

    private var checklistItems: [ChecklistItem] {
        [
            ChecklistItem(
                done: permissions.status.isReady,
                title: "Permissions",
                detail: permissionDetail,
                trail: permissions.status.isReady ? nil : AnyView(
                    HStack(spacing: Ink.space2) {
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
                title: "First take",
                detail: sessions.isEmpty
                    ? firstSessionDetail
                    : "\(sessions.count) session\(sessions.count == 1 ? "" : "s") in History.",
                trail: nil
            ),
        ]
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
            return "da transcribuh is finishing this take. the menu bar icon shows the same state."
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
