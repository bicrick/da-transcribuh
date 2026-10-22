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
        VStack(alignment: .leading, spacing: 0) {
            Text("History")
                .font(Ink.pageTitleFont)
                .foregroundStyle(Ink.label)
                .padding(.horizontal, Ink.pageSide)
                .padding(.top, Ink.pageTop)
                .padding(.bottom, 16)
            if sessions.isEmpty {
                InkDashedEmpty(
                    title: "No sessions yet",
                    detail: "Press \(AppSettings.shared.chord.display) — or Start on Home — for your first take. Transcripts land here when you stop."
                )
                .padding(.horizontal, Ink.pageSide)
                Spacer()
            } else {
                HStack(alignment: .top, spacing: 0) {
                    listColumn
                    Rectangle()
                        .fill(Ink.hairline)
                        .frame(width: 1)
                    detailColumn
                }
                .frame(maxHeight: .infinity)
            }
        }
        .inkPageChrome()
        .onAppear {
            reload()
            if selectedID == nil {
                selectedID = sessions.first?.id
            }
        }
    }

    private var listColumn: some View {
        VStack(spacing: 10) {
            TextField("Search transcripts", text: $query)
                .textFieldStyle(.plain)
                .inkFieldStyle()
                .padding(.horizontal, 12)
            if matches.isEmpty {
                Text("No matches")
                    .font(Ink.captionFont)
                    .foregroundStyle(Ink.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .padding(12)
            } else {
                DTScrollView {
                    LazyVStack(spacing: Ink.space2) {
                        ForEach(matches) { session in
                            historyRow(session)
                        }
                    }
                    .padding(.horizontal, Ink.space3)
                    .padding(.bottom, Ink.space3)
                }
            }
        }
        .frame(width: 300)
        .frame(maxHeight: .infinity, alignment: .top)
        .padding(.top, 4)
    }

    private func historyRow(_ session: SessionSummary) -> some View {
        let isSelected = selected?.id == session.id
        return Button {
            selectedID = session.id
        } label: {
            HStack(spacing: 0) {
                Rectangle()
                    .fill(isSelected ? Ink.accent : Color.clear)
                    .frame(width: 3)
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
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
                    HStack(spacing: 6) {
                        InkBadge(text: "\(session.words) words")
                        InkBadge(text: "\(session.tiles) tiles")
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
            }
            .background(
                (isSelected ? Ink.accentSoft : Ink.card),
                in: RoundedRectangle(cornerRadius: Ink.cardRadius, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Ink.cardRadius, style: .continuous)
                    .strokeBorder(isSelected ? Ink.accent.opacity(0.35) : Ink.hairline, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private var detailColumn: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let selected {
                InkCard {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(longTitle(for: selected))
                                    .font(Ink.labelFont)
                                    .foregroundStyle(Ink.label)
                                Text(detail(for: selected))
                                    .font(Ink.captionFont)
                                    .foregroundStyle(Ink.secondary)
                            }
                            Spacer()
                            HStack(spacing: 8) {
                                Button("Copy") { copy(selected) }
                                    .buttonStyle(InkSecondaryButtonStyle())
                                Button("Show") {
                                    NSWorkspace.shared.activateFileViewerSelecting([selected.url])
                                }
                                .buttonStyle(InkSecondaryButtonStyle())
                            }
                        }
                        InkDivider(leading: 0)
                        DTScrollView {
                            Text(selected.transcript.isEmpty ? "No speech in this session." : selected.transcript)
                                .font(Ink.bodyFont)
                                .foregroundStyle(selected.transcript.isEmpty ? Ink.secondary : Ink.label)
                                .textSelection(.enabled)
                                .fixedSize(horizontal: false, vertical: true)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .frame(minHeight: 200)
                    }
                    .padding(18)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
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
