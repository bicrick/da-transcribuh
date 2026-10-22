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

    /// Pre-#9 hero, minus yellow version badge, tagline, and shortcut caption.
    private var hero: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: Ink.space4) {
                AppLogo(side: 48)
                DTWordmark(size: 20)
                Spacer(minLength: 0)
            }

            HStack(alignment: .center, spacing: Ink.space3) {
                HStack(spacing: Ink.space2) {
                    Rectangle()
                        .fill(Ink.record)
                        .overlay(Rectangle().strokeBorder(Ink.label, lineWidth: 1))
                        .frame(width: 10, height: 10)
                    Text(startRowTitle)
                        .font(Ink.labelFont)
                        .foregroundStyle(Ink.label)
                }
                Spacer(minLength: Ink.space2)
                InkKeycapRow(keys: settings.chord.keycaps)
                Button {
                    session.toggle()
                } label: {
                    HStack(spacing: Ink.space2) {
                        Rectangle()
                            .fill(Ink.record)
                            .overlay(Rectangle().strokeBorder(Ink.onPrimary, lineWidth: 1))
                            .frame(width: 8, height: 8)
                        Text(session.phase == .recording ? "Stop" : "Start")
                            .font(Ink.buttonFont)
                    }
                }
                .buttonStyle(InkPrimaryButtonStyle(large: true, enabled: !session.isBusy))
                .background(
                    Rectangle()
                        .fill(Ink.paintRed)
                        .offset(x: Ink.hardShadow, y: Ink.hardShadow)
                )
                .disabled(session.isBusy)
                .accessibilityLabel(session.phase == .recording ? "Stop session" : "Start session")
                .accessibilityHint("Shortcut \(settings.chord.display)")
            }
            .padding(.top, Ink.space5)
            .overlay(alignment: .top) {
                Rectangle().fill(Ink.hairline).frame(height: 1)
                    .padding(.top, Ink.space4)
            }
        }
    }

    private var stats: some View {
        let numbers = SessionLibrary.stats(from: sessions)
        let items: [(Int, String)] = [
            (numbers.sessions, numbers.sessions == 1 ? "Session" : "Sessions"),
            (numbers.tiles, numbers.tiles == 1 ? "Tile" : "Tiles"),
            (numbers.words, numbers.words == 1 ? "Word" : "Words"),
            (numbers.minutes, numbers.minutes == 1 ? "Minute" : "Minutes"),
        ]
        return HStack(alignment: .top, spacing: Ink.gridGap) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                VStack(alignment: .leading, spacing: Ink.space2) {
                    Text(item.0.formatted(.number.grouping(.automatic)))
                        .font(Ink.numberFont)
                        .monospacedDigit()
                        .foregroundStyle(Ink.label)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    Text(item.1.uppercased())
                        .font(Ink.headingFont)
                        .foregroundStyle(Ink.secondary)
                    // Full-column neutral rule — per-stat colors moved to folder tabs.
                    Rectangle()
                        .fill(Ink.statRule)
                        .overlay(Rectangle().strokeBorder(Ink.label, lineWidth: 1))
                        .frame(maxWidth: .infinity)
                        .frame(height: 4)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var checklist: some View {
        let items = checklistItems
        let done = items.filter(\.done).count
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: Ink.space3) {
                Text("\(done) of \(items.count) done".uppercased())
                    .font(Ink.headingFont)
                    .foregroundStyle(Ink.label)
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Rectangle()
                            .fill(Ink.window)
                            .overlay(Rectangle().strokeBorder(Ink.label, lineWidth: 1.5))
                        Rectangle()
                            .fill(Ink.paintLime)
                            .frame(width: max(0, geo.size.width * (items.isEmpty ? 0 : CGFloat(done) / CGFloat(items.count))))
                            .overlay(alignment: .trailing) {
                                Rectangle().fill(Ink.label).frame(width: 1)
                            }
                    }
                }
                .frame(height: 8)
            }
            .padding(.bottom, Ink.space3)

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
                .padding(.vertical, Ink.space3)
                .overlay(alignment: .bottom) {
                    Rectangle().fill(Ink.hairline).frame(height: 1)
                }
            }
        }
    }

    private var tips: some View {
        HStack(alignment: .top, spacing: Ink.gridGap) {
            tipColumn(
                glyph: "viewfinder",
                title: "Talk, or drag to capture",
                detail: "Hold Shift to mark the screen, then drag. Speech alone pastes the transcript. A capture pastes the picture with the words.",
                trailing: nil
            )
            tipColumn(
                glyph: "folder.fill",
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

    private func tipColumn(
        glyph: String,
        title: String,
        detail: String,
        trailing: AnyView?
    ) -> some View {
        VStack(alignment: .leading, spacing: Ink.space2) {
            ZStack {
                Rectangle()
                    .fill(Ink.tileFace)
                Rectangle()
                    .strokeBorder(Ink.controlBorder, lineWidth: 1.5)
                Image(systemName: glyph)
                    .font(.system(size: Ink.tipSymbolPointSize, weight: .black))
                    .symbolRenderingMode(.monochrome)
                    .foregroundStyle(Ink.onTile)
            }
            .frame(width: Ink.tipIconSize, height: Ink.tipIconSize)
            Text(title)
                .font(Ink.labelFont)
                .foregroundStyle(Ink.label)
            Text(detail)
                .font(Ink.captionFont)
                .foregroundStyle(Ink.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let trailing {
                trailing
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
