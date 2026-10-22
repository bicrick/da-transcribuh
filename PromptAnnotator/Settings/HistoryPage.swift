import AppKit
import SwiftUI

struct HistoryPage: View {
    var sessions: [SessionSummary]
    var reload: () -> Void
    @Binding var query: String
    @Binding var focusSearch: Bool
    @Binding var selectedID: String?
    @FocusState private var searchFocused: Bool

    /// Fixed terminal-log columns (Departure Mono digits align).
    private enum Col {
        static let when: CGFloat = 132
        static let dur: CGFloat = 56
        static let tiles: CGFloat = 52
        static let words: CGFloat = 64
        static let actions: CGFloat = 118
    }

    private var matches: [SessionSummary] {
        HistorySearch.filter(sessions, query: query)
    }

    private var selected: SessionSummary? {
        let rows = matches
        if let selectedID, let match = rows.first(where: { $0.id == selectedID }) {
            return match
        }
        return rows.first
    }

    var body: some View {
        Group {
            if sessions.isEmpty {
                emptyState
            } else {
                populated
            }
        }
        .inkPageChrome()
        // No reload here: SettingsRoot already loads on appear / show /
        // sessionsChanged, and a second decode of every session.json on each
        // tab switch was pure repeat work.
        .onAppear { syncSelection() }
        .onChange(of: query) { _, _ in syncSelection() }
        .onChange(of: sessions.count) { _, _ in syncSelection() }
        .onChange(of: focusSearch) { _, wants in
            if wants {
                searchFocused = true
                focusSearch = false
            }
        }
        .onChange(of: selectedID) { _, _ in syncSelection() }
    }

    private var emptyState: some View {
        SettingsPageStack(
            title: "History",
            subtitle: "Takes land here when you stop a session."
        ) {
            InkDashedEmpty(
                title: "No sessions yet",
                detail: "Press \(AppSettings.shared.chord.display) — or Start on Home — for your first take. Transcripts land here when you stop."
            )
        }
    }

    private var populated: some View {
        DTScrollView {
            VStack(alignment: .leading, spacing: Ink.sectionGap) {
                InkPageHeader(
                    title: "History",
                    subtitle: "\(sessions.count) session\(sessions.count == 1 ? "" : "s") on disk. Select a row to read the transcript."
                )
                searchField
                logTable
                detailPane
            }
            .padding(.top, Ink.pageTop)
            .padding(.horizontal, Ink.pageSide)
            .padding(.bottom, Ink.pageBottom)
            .frame(maxWidth: Ink.maxContentWidth, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .center)
        }
    }

    private var searchField: some View {
        HStack(spacing: Ink.space2) {
            Text("⌕")
                .font(Ink.labelFont)
                .foregroundStyle(Ink.secondary)
            TextField("Search transcripts", text: $query)
                .textFieldStyle(.plain)
                .font(Ink.bodyFont)
                .foregroundStyle(Ink.label)
                .focused($searchFocused)
        }
        .inkFieldStyle()
    }

    private var logTable: some View {
        VStack(spacing: 0) {
            logHeader
            if matches.isEmpty {
                Text("No matches")
                    .font(Ink.captionFont)
                    .foregroundStyle(Ink.secondary)
                    .frame(maxWidth: .infinity, minHeight: 120, alignment: .topLeading)
                    .padding(Ink.rowHPad)
            } else {
                DTScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(matches) { session in
                            logRow(session)
                        }
                    }
                }
                .frame(minHeight: 220, maxHeight: 320)
            }
        }
        .overlay(
            Rectangle()
                .strokeBorder(Ink.label, lineWidth: Ink.stroke)
        )
    }

    private var logHeader: some View {
        HStack(spacing: 0) {
            headerCell("WHEN", width: Col.when)
            headerCell("DUR", width: Col.dur)
            headerCell("TILES", width: Col.tiles)
            headerCell("WORDS", width: Col.words)
            Text("TEXT")
                .font(Ink.headingFont)
                .foregroundStyle(Ink.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, Ink.space2)
            Text("ACT")
                .font(Ink.headingFont)
                .foregroundStyle(Ink.secondary)
                .frame(width: Col.actions, alignment: .trailing)
                .padding(.trailing, Ink.space2)
        }
        // Match DTScrollView's reserved scroller gutter so ACT lines up with row buttons.
        .padding(.trailing, Ink.scrollerGutter)
        .frame(height: 28)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Ink.label).frame(height: 1)
        }
        .background(Ink.fill)
    }

    private func headerCell(_ title: String, width: CGFloat) -> some View {
        Text(title)
            .font(Ink.headingFont)
            .foregroundStyle(Ink.secondary)
            .frame(width: width, alignment: .leading)
            .padding(.leading, Ink.space2)
    }

    private func logRow(_ session: SessionSummary) -> some View {
        let isSelected = selected?.id == session.id
        return HStack(spacing: 0) {
            Button {
                selectedID = session.id
            } label: {
                HStack(spacing: 0) {
                    Text(whenText(for: session))
                        .font(Ink.labelFont)
                        .foregroundStyle(Ink.label)
                        .monospacedDigit()
                        .frame(width: Col.when, alignment: .leading)
                        .padding(.leading, Ink.space2)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Text(TimeFormat.clock(session.duration))
                        .font(Ink.labelFont)
                        .foregroundStyle(Ink.secondary)
                        .monospacedDigit()
                        .frame(width: Col.dur, alignment: .leading)
                        .padding(.leading, Ink.space2)
                    Text("\(session.tiles)")
                        .font(Ink.labelFont)
                        .foregroundStyle(Ink.secondary)
                        .monospacedDigit()
                        .frame(width: Col.tiles, alignment: .leading)
                        .padding(.leading, Ink.space2)
                    Text("\(session.words)")
                        .font(Ink.labelFont)
                        .foregroundStyle(Ink.secondary)
                        .monospacedDigit()
                        .frame(width: Col.words, alignment: .leading)
                        .padding(.leading, Ink.space2)
                    Text(session.preview.isEmpty ? "—" : session.preview)
                        .font(Ink.captionFont)
                        .foregroundStyle(session.preview.isEmpty ? Ink.tertiary : Ink.secondary)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, Ink.space2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            HStack(spacing: Ink.space2) {
                Button("Copy") { copy(session) }
                    .buttonStyle(InkSecondaryButtonStyle())
                Button("Show") {
                    NSWorkspace.shared.activateFileViewerSelecting([session.url])
                }
                .buttonStyle(InkSecondaryButtonStyle())
            }
            .frame(width: Col.actions, alignment: .trailing)
            .padding(.trailing, Ink.space2)
        }
        .frame(minHeight: 36)
        .padding(.vertical, Ink.space1)
        .background(isSelected ? Ink.fill : Color.clear)
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(isSelected ? Ink.label : Color.clear)
                .frame(width: 2)
        }
        .overlay(alignment: .bottom) {
            Rectangle().fill(Ink.hairline).frame(height: 1)
        }
        .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
    }

    private var detailPane: some View {
        Group {
            if let selected {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(alignment: .firstTextBaseline, spacing: Ink.space3) {
                        Text(longTitle(for: selected))
                            .font(Ink.labelFont)
                            .foregroundStyle(Ink.label)
                        Text(detail(for: selected))
                            .font(Ink.captionFont)
                            .foregroundStyle(Ink.secondary)
                        Spacer(minLength: 0)
                        HStack(spacing: Ink.space2) {
                            Button("Copy") { copy(selected) }
                                .buttonStyle(InkSecondaryButtonStyle())
                            Button("Show in Finder") {
                                NSWorkspace.shared.activateFileViewerSelecting([selected.url])
                            }
                            .buttonStyle(InkSecondaryButtonStyle())
                        }
                    }
                    .padding(Ink.cardPad)
                    .overlay(alignment: .bottom) {
                        Rectangle().fill(Ink.label).frame(height: 1)
                    }

                    DTScrollView {
                        Text(selected.transcript.isEmpty ? "No speech in this session." : selected.transcript)
                            .font(Ink.bodyFont)
                            .foregroundStyle(selected.transcript.isEmpty ? Ink.secondary : Ink.label)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .topLeading)
                            .padding(Ink.cardPad)
                    }
                    .frame(minHeight: 160, maxHeight: 280)
                }
                .overlay(
                    Rectangle()
                        .strokeBorder(Ink.label, lineWidth: Ink.stroke)
                )
            } else {
                InkDashedEmpty(
                    title: "Select a session",
                    detail: "Pick a row in the log to read the transcript."
                )
            }
        }
    }

    private func syncSelection() {
        let ids = matches.map(\.id)
        if let selectedID, ids.contains(selectedID) { return }
        self.selectedID = ids.first
    }

    private func whenText(for session: SessionSummary) -> String {
        guard let started = session.started else { return session.id }
        return Self.whenFormatter.string(from: started)
    }

    /// One formatter for every row (creating one per row showed in traces).
    private static let whenFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d HH:mm"
        return formatter
    }()

    private func longTitle(for session: SessionSummary) -> String {
        guard let started = session.started else { return session.id }
        return started.formatted(date: .abbreviated, time: .shortened)
    }

    private func detail(for session: SessionSummary) -> String {
        let tileNoun = session.tiles == 1 ? "tile" : "tiles"
        let wordNoun = session.words == 1 ? "word" : "words"
        return "\(TimeFormat.clock(session.duration)) · \(session.tiles) \(tileNoun) · \(session.words) \(wordNoun)"
    }

    private func copy(_ session: SessionSummary) {
        let image = NSImage(contentsOf: session.url.appendingPathComponent("sheet.png"))
        SessionClipboard.copy(image: image, transcript: session.transcript)
    }
}
