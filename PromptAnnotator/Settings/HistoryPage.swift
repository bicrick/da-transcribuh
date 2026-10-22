import AppKit
import SwiftUI

struct HistoryPage: View {
    var sessions: [SessionSummary]
    var reload: () -> Void
    @State private var query = ""
    @State private var selectedID: String?

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
        .onAppear {
            reload()
            syncSelection()
        }
        .onChange(of: query) { _, _ in syncSelection() }
        .onChange(of: sessions.count) { _, _ in syncSelection() }
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
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: Ink.titleDescGap) {
                Text("History")
                    .font(Ink.pageTitleFont)
                    .foregroundStyle(Ink.label)
                Text("\(sessions.count) session\(sessions.count == 1 ? "" : "s") on disk.")
                    .font(Ink.bodyFont)
                    .foregroundStyle(Ink.secondary)
                searchField
            }
            .padding(.top, Ink.pageTop)
            .padding(.horizontal, Ink.pageSide)
            .padding(.bottom, Ink.space3)
            .frame(maxWidth: Ink.maxContentWidth, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .center)

            HStack(alignment: .top, spacing: 0) {
                listColumn
                Rectangle()
                    .fill(Ink.label)
                    .frame(width: 1)
                detailColumn
            }
            .frame(maxWidth: Ink.maxContentWidth)
            .frame(maxWidth: .infinity, alignment: .center)
            .frame(maxHeight: .infinity)
            .padding(.horizontal, Ink.pageSide)
            .padding(.bottom, Ink.pageBottom)
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
        }
        .inkFieldStyle()
    }

    private var listColumn: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Sessions".uppercased())
                    .font(Ink.headingFont)
                    .foregroundStyle(Ink.secondary)
                Spacer()
                Text("\(matches.count)")
                    .font(Ink.headingFont)
                    .foregroundStyle(Ink.secondary)
            }
            .padding(.horizontal, Ink.rowHPad)
            .padding(.vertical, Ink.space2)
            .overlay(alignment: .bottom) {
                Rectangle().fill(Ink.label).frame(height: 1)
            }

            if matches.isEmpty {
                Text("No matches")
                    .font(Ink.captionFont)
                    .foregroundStyle(Ink.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .padding(Ink.rowHPad)
            } else {
                DTScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(matches) { session in
                            historyRow(session)
                            Rectangle()
                                .fill(Ink.hairline)
                                .frame(height: 1)
                        }
                    }
                }
            }
        }
        .frame(width: 300)
        .frame(maxHeight: .infinity, alignment: .top)
        .overlay(
            Rectangle()
                .strokeBorder(Ink.label, lineWidth: 1)
        )
    }

    private func historyRow(_ session: SessionSummary) -> some View {
        let isSelected = selected?.id == session.id
        return Button {
            selectedID = session.id
        } label: {
            HStack(alignment: .top, spacing: Ink.space3) {
                InkRadio(selected: isSelected)
                    .padding(.top, 2)
                VStack(alignment: .leading, spacing: Ink.titleDescGap) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(title(for: session))
                            .font(Ink.rowTitleFont)
                            .foregroundStyle(Ink.label)
                        Spacer(minLength: 4)
                        Text(TimeFormat.clock(session.duration))
                            .font(Ink.captionFont)
                            .foregroundStyle(Ink.secondary)
                    }
                    Text(session.preview.isEmpty ? "No speech" : session.preview)
                        .font(Ink.captionFont)
                        .foregroundStyle(Ink.secondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    HStack(spacing: Ink.space2) {
                        InkBadge(text: "\(session.words) w")
                        InkBadge(text: "\(session.tiles) tiles")
                    }
                }
            }
            .padding(.horizontal, Ink.rowHPad)
            .padding(.vertical, Ink.space3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isSelected ? Ink.fill : Color.clear)
            .overlay(alignment: .leading) {
                Rectangle()
                    .fill(isSelected ? Ink.label : Color.clear)
                    .frame(width: 2)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
    }

    private var detailColumn: some View {
        Group {
            if let selected {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(alignment: .top, spacing: Ink.space3) {
                        VStack(alignment: .leading, spacing: Ink.titleDescGap) {
                            Text(longTitle(for: selected))
                                .font(Ink.labelFont)
                                .foregroundStyle(Ink.label)
                            Text(detail(for: selected))
                                .font(Ink.captionFont)
                                .foregroundStyle(Ink.secondary)
                        }
                        Spacer(minLength: 0)
                        HStack(spacing: Ink.space2) {
                            Button("Copy") { copy(selected) }
                                .buttonStyle(InkSecondaryButtonStyle())
                            Button("Show") {
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
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .overlay(
                    Rectangle()
                        .strokeBorder(Ink.label, lineWidth: 1)
                )
            } else {
                InkDashedEmpty(
                    title: "Select a session",
                    detail: "Pick a take from the list to read the transcript."
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(.leading, Ink.space3)
    }

    private func syncSelection() {
        let ids = matches.map(\.id)
        if let selectedID, ids.contains(selectedID) { return }
        self.selectedID = ids.first
    }

    private func title(for session: SessionSummary) -> String {
        guard let started = session.started else { return session.id }
        return started.formatted(date: .abbreviated, time: .omitted)
    }

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
