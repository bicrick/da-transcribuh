import AppKit
import SwiftUI

struct HomePage: View {
    @ObservedObject var session: SessionController
    @ObservedObject var settings: AppSettings
    @ObservedObject var permissions: PermissionModel
    var sessions: [SessionSummary]
    /// Open History; pass a session id to select that row, or nil for the list.
    var onOpenHistory: (String?) -> Void = { _ in }
    var onOpenModels: () -> Void = {}
    var onOpenSound: () -> Void = {}

    @State private var getStartedComplete = HomeGetStartedStore.isComplete()
    @State private var hoveredRecentID: String?
    /// Measured content-column width (inside page padding). Seed wide so the first
    /// frame doesn’t flash the stacked layout before the probe runs.
    @State private var contentWidth: CGFloat = 2400

    /// Bento gutters — airy but tighter than sectionGap so cells read as one composition.
    private var cellGap: CGFloat { Ink.space3 }
    private var isNarrow: Bool { HomeBentoLayout.isNarrow(contentWidth: contentWidth) }

    var body: some View {
        DTScrollView {
            VStack(alignment: .leading, spacing: Ink.sectionGap) {
                hero
                bentoBody
            }
            .padding(.top, Ink.pageTop)
            .padding(.horizontal, Ink.pageSide)
            .padding(.bottom, Ink.pageBottom)
            // One content column: same max as other Settings pages so hero divider
            // and bento edges share one alignment.
            .frame(maxWidth: Ink.maxContentWidth, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .center)
            .background {
                GeometryReader { geo in
                    Color.clear.preference(
                        key: HomeContentWidthKey.self,
                        value: geo.size.width
                    )
                }
            }
            .onPreferenceChange(HomeContentWidthKey.self) { width in
                if width > 1, abs(width - contentWidth) > 0.5 {
                    contentWidth = width
                }
            }
        }
        .inkPageChrome()
        .onAppear {
            permissions.refresh()
            syncGetStartedFlag()
        }
        .onChange(of: sessions.count) { _, _ in syncGetStartedFlag() }
        .onChange(of: settings.clipboardHistoryEnabled) { _, _ in syncGetStartedFlag() }
        .onReceive(permissions.objectWillChange) { _ in
            DispatchQueue.main.async { syncGetStartedFlag() }
        }
    }

    private var showGetStarted: Bool { !getStartedComplete }

    private func syncGetStartedFlag() {
        guard !getStartedComplete else { return }
        if checklistItems.allSatisfy(\.done) {
            HomeGetStartedStore.markComplete()
            getStartedComplete = true
        }
    }

    // MARK: - Hero (unchanged)

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
                        .overlay(Rectangle().strokeBorder(Ink.label, lineWidth: Ink.stroke))
                        .frame(width: 10, height: 10)
                    Text(startRowTitle)
                        .font(Ink.labelFont)
                        .foregroundStyle(Ink.label)
                }
                Spacer(minLength: Ink.space2)
                HomeChordEditor(settings: settings)
                Button {
                    session.toggle()
                } label: {
                    HStack(spacing: Ink.space2) {
                        Rectangle()
                            .fill(Ink.record)
                            .overlay(Rectangle().strokeBorder(Ink.onPrimary, lineWidth: Ink.stroke))
                            .frame(width: 8, height: 8)
                        Text(session.phase == .recording ? "Stop" : "Start")
                            .font(Ink.buttonFont)
                    }
                }
                .buttonStyle(InkPrimaryButtonStyle(large: true, enabled: !session.isBusy))
                .background(
                    Rectangle()
                        .fill(Ink.paintRed)
                        .offset(x: Ink.bevelOffset, y: Ink.bevelOffset)
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

    // MARK: - Bento body

    private var bentoBody: some View {
        VStack(alignment: .leading, spacing: cellGap) {
            statsRow
            if showGetStarted {
                HomeBentoCell(title: "GET STARTED") {
                    checklist
                }
            } else {
                recentAndWeekRow
            }
            actionsAndStatusRow
        }
    }

    /// Row 1: four equal stat cells. Narrow → 2×2.
    ///
    /// Do **not** use `ViewThatFits` here: long ideal widths from sibling rows
    /// aren’t the issue for stats, but a measured breakpoint keeps all bento
    /// rows on one consistent rule (`stackBreakpoint`).
    private var statsRow: some View {
        let numbers = SessionLibrary.stats(from: sessions)
        let items: [(Int, String)] = [
            (numbers.sessions, numbers.sessions == 1 ? "Session" : "Sessions"),
            (numbers.tiles, numbers.tiles == 1 ? "Tile" : "Tiles"),
            (numbers.words, numbers.words == 1 ? "Word" : "Words"),
            (numbers.minutes, numbers.minutes == 1 ? "Minute" : "Minutes"),
        ]
        return Group {
            if isNarrow {
                VStack(spacing: cellGap) {
                    HStack(alignment: .top, spacing: cellGap) {
                        statCell(value: items[0].0, label: items[0].1)
                        statCell(value: items[1].0, label: items[1].1)
                    }
                    HStack(alignment: .top, spacing: cellGap) {
                        statCell(value: items[2].0, label: items[2].1)
                        statCell(value: items[3].0, label: items[3].1)
                    }
                }
            } else {
                HStack(alignment: .top, spacing: cellGap) {
                    ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                        statCell(value: item.0, label: item.1)
                    }
                }
            }
        }
    }

    private func statCell(value: Int, label: String) -> some View {
        HomeBentoCell(title: label.uppercased(), compact: true) {
            VStack(alignment: .leading, spacing: Ink.space2) {
                Text(value.formatted(.number.grouping(.automatic)))
                    .font(Ink.numberFont)
                    .monospacedDigit()
                    .foregroundStyle(Ink.label)
                    .lineLimit(1)
                    .minimumScaleFactor(0.55)
                Rectangle()
                    .fill(Ink.statRule)
                    .frame(width: 28, height: 3)
                    .overlay(Rectangle().strokeBorder(Ink.label, lineWidth: Ink.stroke))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Row 2: RECENT (~2/3) + THIS WEEK (~1/3). Narrow → stack.
    ///
    /// Root cause of the false-narrow bug: `ViewThatFits` compares each child’s
    /// *ideal* width to the proposal. RECENT preview strings and CAPTURE body
    /// copy have huge untruncated ideal widths, so the horizontal alternative
    /// always “didn’t fit” and SwiftUI picked the stacked VStack even at ~1000pt.
    private var recentAndWeekRow: some View {
        Group {
            if isNarrow {
                VStack(alignment: .leading, spacing: cellGap) {
                    recentCell
                    thisWeekCell
                }
            } else {
                HStack(alignment: .top, spacing: cellGap) {
                    recentCell
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    thisWeekCell
                        .frame(minWidth: 220, maxWidth: 220, maxHeight: .infinity, alignment: .topLeading)
                }
                // Stretch both cells to the taller sibling (RECENT).
                .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var recentCell: some View {
        let rows = SessionLibrary.recent(sessions, limit: 4)
        return HomeBentoCell(
            title: "RECENT",
            trailing: AnyView(
                Button("All in History →") { onOpenHistory(nil) }
                    .buttonStyle(.plain)
                    .font(Ink.captionFont)
                    .foregroundStyle(Ink.secondary)
            )
        ) {
            if rows.isEmpty {
                Text("No sessions yet — press Start for your first take.")
                    .font(Ink.captionFont)
                    .foregroundStyle(Ink.secondary)
                    .padding(.vertical, Ink.space2)
            } else {
                VStack(spacing: 0) {
                    ForEach(rows) { summary in
                        recentRow(summary)
                    }
                }
            }
        }
    }

    private var thisWeekCell: some View {
        let counts = SessionLibrary.weeklyWordCounts(from: sessions)
        let total = counts.reduce(0, +)
        let maxCount = max(counts.max() ?? 0, 1)
        let best = counts.max() ?? 0
        let initials = weekDayInitials()
        let chartHeight: CGFloat = 56
        return HomeBentoCell(
            title: "THIS WEEK",
            trailing: AnyView(
                Text("\(total.formatted(.number.grouping(.automatic))) words")
                    .font(Ink.captionFont)
                    .foregroundStyle(Ink.secondary)
                    .monospacedDigit()
            )
        ) {
            VStack(alignment: .leading, spacing: Ink.space3) {
                Spacer(minLength: 0)
                HStack(alignment: .bottom, spacing: 6) {
                    ForEach(0..<7, id: \.self) { index in
                        let value = counts[index]
                        let isToday = index == 6
                        let barHeight: CGFloat = {
                            if value <= 0 {
                                return 2 // faint baseline tick for empty days
                            }
                            return max(2, CGFloat(value) / CGFloat(maxCount) * chartHeight)
                        }()
                        VStack(spacing: 4) {
                            RoundedRectangle(cornerRadius: 1, style: .continuous)
                                .fill(isToday ? Ink.paintRed : Ink.label)
                                .frame(width: 12, height: barHeight)
                                .opacity(value == 0 ? 0.22 : (isToday ? 1 : 0.75))
                            Text(initials[index])
                                .font(Ink.captionFont)
                                .foregroundStyle(isToday ? Ink.label : Ink.tertiary)
                        }
                        .frame(width: 14, height: chartHeight + 18, alignment: .bottom)
                        .accessibilityLabel("\(initials[index]), \(value) words")
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if best > 0 {
                    Text("Best day · \(best.formatted(.number.grouping(.automatic))) words")
                        .font(Ink.captionFont)
                        .foregroundStyle(Ink.tertiary)
                } else {
                    Text("No words this week yet")
                        .font(Ink.captionFont)
                        .foregroundStyle(Ink.tertiary)
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
    }

    /// Row 3: two action cells; status caption lives under the capture cell (least clutter).
    private var actionsAndStatusRow: some View {
        Group {
            if isNarrow {
                VStack(alignment: .leading, spacing: cellGap) {
                    captureActionCell
                    folderActionCell
                }
            } else {
                HStack(alignment: .top, spacing: cellGap) {
                    captureActionCell
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    folderActionCell
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                }
                .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var captureActionCell: some View {
        HomeBentoCell(title: "CAPTURE") {
            VStack(alignment: .leading, spacing: Ink.space2) {
                actionGlyph("viewfinder")
                Text("Talk, or drag to capture")
                    .font(Ink.labelFont)
                    .foregroundStyle(Ink.label)
                    .lineLimit(2)
                Text("Hold Shift to mark the screen, then drag. Speech alone pastes the transcript. A capture pastes the picture with the words.")
                    .font(Ink.captionFont)
                    .foregroundStyle(Ink.secondary)
                    .lineLimit(4)
                    .fixedSize(horizontal: false, vertical: true)
                    .layoutPriority(-1)
                statusCaption
                    .padding(.top, Ink.space2)
            }
        }
    }

    private var folderActionCell: some View {
        HomeBentoCell(title: "FOLDER") {
            VStack(alignment: .leading, spacing: Ink.space2) {
                actionGlyph("folder.fill")
                Text("Sessions folder")
                    .font(Ink.labelFont)
                    .foregroundStyle(Ink.label)
                    .lineLimit(1)
                Text(SessionStore.displayPath())
                    .font(Ink.captionFont)
                    .foregroundStyle(Ink.secondary)
                    .lineLimit(2)
                    .truncationMode(.middle)
                    .layoutPriority(-1)
                Button("Show") {
                    if let root = try? SessionPaths.sessionsRoot() {
                        NSWorkspace.shared.open(root)
                    }
                }
                .buttonStyle(InkSecondaryButtonStyle())
                .padding(.top, Ink.space1)
            }
        }
    }

    private func actionGlyph(_ symbol: String) -> some View {
        ZStack {
            Rectangle()
                .fill(Ink.tileFace)
            Rectangle()
                .strokeBorder(Ink.controlBorder, lineWidth: Ink.stroke)
            Image(systemName: symbol)
                .font(.system(size: Ink.tipSymbolPointSize, weight: .black))
                .symbolRenderingMode(.monochrome)
                .foregroundStyle(Ink.onTile)
        }
        .frame(width: Ink.tipIconSize, height: Ink.tipIconSize)
    }

    private var statusCaption: some View {
        Group {
            if let issue = homeStatusIssue {
                HStack(alignment: .center, spacing: Ink.space2) {
                    Circle()
                        .fill(Ink.paintRed)
                        .frame(width: 7, height: 7)
                    Text(issue.message)
                        .font(Ink.captionFont)
                        .foregroundStyle(Ink.label)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: Ink.space1)
                    Button(issue.actionTitle) { issue.action() }
                        .buttonStyle(InkSecondaryButtonStyle())
                }
            } else {
                Text(homeStatusOK)
                    .font(Ink.captionFont)
                    .foregroundStyle(Ink.tertiary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: - Recent row

    private func recentRow(_ summary: SessionSummary) -> some View {
        let hovering = hoveredRecentID == summary.id
        return HStack(alignment: .center, spacing: Ink.space2) {
            Button {
                onOpenHistory(summary.id)
            } label: {
                HStack(alignment: .center, spacing: Ink.space2) {
                    Text(SessionLibrary.recentWhen(summary.started))
                        .font(Ink.captionFont)
                        .foregroundStyle(Ink.secondary)
                        .monospacedDigit()
                        .frame(width: 44, alignment: .leading)
                        .lineLimit(1)

                    Text(summary.preview.isEmpty ? "No speech" : summary.preview)
                        .font(Ink.captionFont)
                        .foregroundStyle(summary.preview.isEmpty ? Ink.tertiary : Ink.label)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .layoutPriority(-1)

                    Text("\(summary.words)")
                        .font(Ink.captionFont)
                        .foregroundStyle(Ink.secondary)
                        .monospacedDigit()
                        .frame(width: 36, alignment: .trailing)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if hovering {
                Button("Copy") { copy(summary) }
                    .buttonStyle(InkSecondaryButtonStyle())
            }

            recentThumb(summary)
        }
        .padding(.vertical, Ink.space2)
        .onHover { over in
            if over {
                hoveredRecentID = summary.id
            } else if hoveredRecentID == summary.id {
                hoveredRecentID = nil
            }
        }
        .overlay(alignment: .bottom) {
            Rectangle().fill(Ink.hairline).frame(height: 1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(recentAccessibility(summary))
        .accessibilityAddTraits(.isButton)
    }

    @ViewBuilder
    private func recentThumb(_ summary: SessionSummary) -> some View {
        let side: CGFloat = 28
        if let url = SessionLibrary.thumbnailURL(for: summary),
           let image = HomeThumbCache.image(at: url) {
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: side, height: side)
                .clipped()
                .overlay(Rectangle().strokeBorder(Ink.label, lineWidth: Ink.stroke))
        } else {
            Color.clear.frame(width: side, height: side)
        }
    }

    private func recentAccessibility(_ summary: SessionSummary) -> String {
        let when = SessionLibrary.recentWhen(summary.started)
        let text = summary.preview.isEmpty ? "No speech" : summary.preview
        return "\(when), \(text), \(summary.words) words"
    }

    private func copy(_ summary: SessionSummary) {
        let image = NSImage(contentsOf: summary.url.appendingPathComponent("sheet.png"))
        SessionClipboard.copy(image: image, transcript: summary.transcript)
    }

    private func weekDayInitials(now: Date = Date(), calendar: Calendar = .current) -> [String] {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEEE"
        let today = calendar.startOfDay(for: now)
        return (0..<7).map { offset in
            let day = calendar.date(byAdding: .day, value: offset - 6, to: today) ?? today
            return formatter.string(from: day).uppercased()
        }
    }

    // MARK: - Status helpers

    private var homeStatusOK: String {
        "\(modelStatusLabel) · \(micDisplayName) · Permissions OK"
    }

    private var modelStatusLabel: String {
        if settings.speechEngine == .openAICompatible {
            return OpenAICompatibleTranscriber.isConfigured()
                ? "Server model ready"
                : "Server key missing"
        }
        if WhisperKitTranscriber.modelIsInstalled() {
            return settings.speechModel
        }
        return "Model not downloaded"
    }

    private var micDisplayName: String {
        let uid = settings.inputDeviceUID
        if uid.isEmpty { return "System mic" }
        return AudioInputs.devices().first(where: { $0.id == uid })?.name ?? "Mic unavailable"
    }

    private struct HomeStatusIssue {
        var message: String
        var actionTitle: String
        var action: () -> Void
    }

    private var homeStatusIssue: HomeStatusIssue? {
        if !permissions.status.isReady {
            let missing = permissions.status.summary ?? "permissions"
            return HomeStatusIssue(
                message: "Turn on \(missing).",
                actionTitle: "Fix",
                action: {
                    Permissions.revealSettings(for: Permissions.current())
                    permissions.refresh()
                }
            )
        }
        if settings.speechEngine == .openAICompatible {
            if !OpenAICompatibleTranscriber.isConfigured() {
                return HomeStatusIssue(
                    message: "Add a server API key on Models.",
                    actionTitle: "Models",
                    action: onOpenModels
                )
            }
        } else if !WhisperKitTranscriber.modelIsInstalled() {
            return HomeStatusIssue(
                message: "Download a speech model on Models.",
                actionTitle: "Models",
                action: onOpenModels
            )
        }
        let uid = settings.inputDeviceUID
        if !uid.isEmpty, AudioInputs.devices().first(where: { $0.id == uid }) == nil {
            return HomeStatusIssue(
                message: "Chosen mic is unavailable.",
                actionTitle: "Sound",
                action: onOpenSound
            )
        }
        return nil
    }

    // MARK: - Get started checklist

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
                            .overlay(Rectangle().strokeBorder(Ink.label, lineWidth: Ink.stroke))
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
                done: settings.clipboardHistoryEnabled,
                title: "Clipboard history",
                detail: settings.clipboardHistoryEnabled
                    ? "\(settings.clipboardChord.display) opens history. Off anytime in General."
                    : "Turn on in General — or finish welcome setup. Uses Accessibility you already grant for paste.",
                trail: nil
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

// MARK: - Bento cell

/// Measured width of the Home content column (inside page padding).
private struct HomeContentWidthKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

/// Whether Home bento rows should stack. Pure helper for tests / snapshot logic.
enum HomeBentoLayout {
    static let stackBreakpoint: CGFloat = 720
    static func isNarrow(contentWidth: CGFloat) -> Bool {
        contentWidth < stackBreakpoint
    }
}

/// Paint/Ink bordered cell: `Ink.front` face, 1pt label border, subtle bevel offset.
private struct HomeBentoCell<Content: View>: View {
    var title: String
    var trailing: AnyView? = nil
    var compact: Bool = false
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? Ink.space2 : Ink.space3) {
            HStack(alignment: .firstTextBaseline, spacing: Ink.space2) {
                Text(title)
                    .font(Ink.headingFont)
                    .foregroundStyle(Ink.label)
                Spacer(minLength: 0)
                if let trailing {
                    trailing
                }
            }
            content()
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .padding(compact ? Ink.space3 : Ink.space4)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Ink.front)
        .overlay(
            Rectangle()
                .strokeBorder(Ink.label, lineWidth: Ink.stroke)
        )
        .background(
            Rectangle()
                .fill(Ink.bevel)
                .offset(x: Ink.bevelOffset, y: Ink.bevelOffset)
        )
        .padding(.trailing, Ink.bevelOffset)
        .padding(.bottom, Ink.bevelOffset)
    }
}

@MainActor
final class PermissionModel: ObservableObject {
    @Published private(set) var status = Permissions.current()

    func refresh() {
        status = Permissions.current()
    }
}

/// Recent-row thumbnails were decoded from disk in `body` on every render.
/// Thumbnails are written once per session, so cache by path.
@MainActor
enum HomeThumbCache {
    private static let cache: NSCache<NSURL, NSImage> = {
        let cache = NSCache<NSURL, NSImage>()
        cache.countLimit = 64
        return cache
    }()

    static func image(at url: URL) -> NSImage? {
        if let hit = cache.object(forKey: url as NSURL) { return hit }
        guard let image = NSImage(contentsOf: url) else { return nil }
        cache.setObject(image, forKey: url as NSURL)
        return image
    }
}
