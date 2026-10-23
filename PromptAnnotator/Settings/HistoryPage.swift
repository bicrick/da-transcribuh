import AppKit
import SwiftUI

struct HistoryPage: View {
    var sessions: [SessionSummary]
    var reload: () -> Void
    @Binding var query: String
    @Binding var focusSearch: Bool
    @Binding var selectedID: String?
    @FocusState private var searchFocused: Bool
    /// The row showing its full transcript inline. Click it again to collapse.
    @State private var expandedID: String?
    /// Set while syncSelection picks a default row, so that pick does not expand it.
    @State private var autoSelect = AutoSelectFlag()

    private final class AutoSelectFlag { var active = false }

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

    /// Rows pass the filtered list in once; the old per-row `selected` refiltered
    /// every session for every row (O(n²) per body).
    private func selected(in rows: [SessionSummary]) -> SessionSummary? {
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
        .onAppear {
            syncSelection()
            applySnapshotExpand()
        }
        .onChange(of: query) { _, _ in syncSelection() }
        .onChange(of: sessions.count) { _, _ in
            syncSelection()
            applySnapshotExpand()
        }
        .onChange(of: focusSearch) { _, wants in
            if wants {
                searchFocused = true
                focusSearch = false
            }
        }
        .onChange(of: selectedID) { _, id in
            // A selection from outside (a search hit) opens that row's transcript.
            if autoSelect.active {
                autoSelect.active = false
            } else if let id {
                expandedID = id
            }
            syncSelection()
        }
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

    /// Header, search and the log. The page does not scroll; the log fills the
    /// remaining height and scrolls on its own rail.
    private var populated: some View {
        VStack(alignment: .leading, spacing: Ink.sectionGap) {
            InkPageHeader(
                title: "History",
                subtitle: "\(sessions.count) session\(sessions.count == 1 ? "" : "s") on disk. Click a row to read the full transcript."
            )
            searchField
            // The reader takes the height the window offers. Without it the
            // log's own minimum climbed to its last viewport and pinned the
            // window's min content height (measured 1484 at 1040x700).
            GeometryReader { proxy in
                logTable
                    .frame(width: proxy.size.width, height: proxy.size.height, alignment: .top)
            }
            .frame(minHeight: 200)
        }
        .padding(.top, Ink.pageTop)
        .padding(.horizontal, Ink.pageSide)
        .padding(.bottom, Ink.pageBottom)
        .frame(maxWidth: Ink.maxContentWidth, maxHeight: .infinity, alignment: .topLeading)
        // minHeight 0 is the size limit. Without it SwiftUI used the page's
        // squeezed height as its minimum. The header text is fixedSize
        // vertically, so at a near-zero width it wraps a word per line, and the
        // settings host turned that into a window min height of 1496 at 1040x700
        // (measured). Other pages sit in a scroll view, which hides this.
        .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity, alignment: .top)
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
        let rows = matches
        let selectedRowID = selected(in: rows)?.id
        return VStack(spacing: 0) {
            logHeader
            if rows.isEmpty {
                Text("No matches")
                    .font(Ink.captionFont)
                    .foregroundStyle(Ink.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .padding(Ink.rowHPad)
            } else {
                // Lazy DTScrollView: native SwiftUI scrolling underneath, so the
                // LazyVStack builds only visible rows (430 sessions took 2.4 s when
                // every row was built), with the Ink rail in the reserved gutter.
                DTScrollView(lazy: true) {
                    LazyVStack(spacing: 0) {
                        ForEach(rows) { session in
                            logRow(
                                session,
                                isSelected: session.id == selectedRowID,
                                isExpanded: session.id == expandedID
                            )
                        }
                    }
                }
                // A SwiftUI ScrollView reports its whole content as ideal height,
                // and the settings host grows the window to the ideal size. Pin
                // the ideal so the log takes the space the window has instead.
                .frame(minHeight: 160, idealHeight: 320, maxHeight: .infinity)
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

    private func logRow(_ session: SessionSummary, isSelected: Bool, isExpanded: Bool) -> some View {
        VStack(spacing: 0) {
            rowLine(session, isExpanded: isExpanded)
            if isExpanded {
                expandedTranscript(session)
            }
        }
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
    }

    private func rowLine(_ session: SessionSummary, isExpanded: Bool) -> some View {
        HStack(spacing: 0) {
            Button {
                toggle(session)
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
        .accessibilityAddTraits(isExpanded ? [.isSelected, .isButton] : .isButton)
        .accessibilityHint(isExpanded ? "Collapses the transcript" : "Shows the full transcript")
    }

    /// The full transcript, wrapped and selectable, under its row.
    private func expandedTranscript(_ session: SessionSummary) -> some View {
        VStack(alignment: .leading, spacing: Ink.space2) {
            Text("\(longTitle(for: session)) · \(detail(for: session))")
                .font(Ink.captionFont)
                .foregroundStyle(Ink.secondary)
            Text(session.transcript.isEmpty ? "No speech in this session." : session.transcript)
                .font(Ink.bodyFont)
                .foregroundStyle(session.transcript.isEmpty ? Ink.secondary : Ink.label)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .padding(.horizontal, Ink.space2)
        .padding(.leading, Ink.space2)
        .padding(.top, Ink.space2)
        .padding(.bottom, Ink.space3)
        .padding(.trailing, Col.actions)
    }

    /// Click opens a row; clicking the open row, or opening another, collapses it.
    private func toggle(_ session: SessionSummary) {
        expandedID = HistoryRowExpansion.next(current: expandedID, tapped: session.id)
        if selectedID != session.id {
            autoSelect.active = true
            selectedID = session.id
        }
    }

    private func syncSelection() {
        let ids = matches.map(\.id)
        if let expandedID, !ids.contains(expandedID) { self.expandedID = nil }
        if let selectedID, ids.contains(selectedID) { return }
        let next = ids.first
        guard next != selectedID else { return }
        autoSelect.active = true
        self.selectedID = next
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

/// Inline expansion rule for History rows: one open row at a time.
extension HistoryPage {
    /// `-DTSnapshotHistoryExpand N` opens row N (1-based) for renders. Sessions
    /// can land after onAppear, so this also runs when the count changes.
    fileprivate func applySnapshotExpand() {
        guard expandedID == nil,
              let n = UserDefaults.standard.string(forKey: "DTSnapshotHistoryExpand").flatMap(Int.init),
              n >= 1, n <= matches.count else { return }
        expandedID = matches[n - 1].id
    }
}

enum HistoryRowExpansion {
    static func next(current: String?, tapped: String) -> String? {
        current == tapped ? nil : tapped
    }
}
