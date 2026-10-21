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
                .font(.system(size: 22, weight: .semibold))
                .padding(.horizontal, SettingsMetrics.pagePadding)
                .padding(.top, SettingsMetrics.pagePadding)
                .padding(.bottom, 12)
            if sessions.isEmpty {
                SettingsCard {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("No sessions yet")
                            .font(.system(size: 13, weight: .semibold))
                        Text("Press \(AppSettings.shared.chord.display) — or Start on Home — for your first take. Transcripts land here when you stop.")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(SettingsMetrics.rowPadding)
                }
                .padding(.horizontal, SettingsMetrics.pagePadding)
                Spacer()
            } else {
                HStack(spacing: 0) {
                    listColumn
                    Rectangle()
                        .fill(Color(nsColor: .separatorColor).opacity(0.7))
                        .frame(width: 1)
                    detailColumn
                }
                .frame(maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            reload()
            if selectedID == nil {
                selectedID = sessions.first?.id
            }
        }
    }

    private var listColumn: some View {
        VStack(spacing: 8) {
            TextField("Search transcripts", text: $query)
                .textFieldStyle(.roundedBorder)
                .padding(.horizontal, 12)
            if matches.isEmpty {
                Text("No matches")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .padding(12)
            } else {
                List(matches, selection: $selectedID) { session in
                    VStack(alignment: .leading, spacing: 3) {
                        HStack {
                            Text(title(for: session))
                                .font(.system(size: 12, weight: .semibold))
                            Spacer(minLength: 4)
                            Text(TimeFormat.clock(session.duration))
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                        Text(session.preview.isEmpty ? "No speech" : session.preview)
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                    .padding(.vertical, 4)
                    .tag(session.id)
                }
                .listStyle(.sidebar)
            }
        }
        .frame(width: 280)
        .frame(maxHeight: .infinity, alignment: .top)
        .padding(.top, 4)
    }

    private var detailColumn: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let selected {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(longTitle(for: selected))
                            .font(.system(size: 16, weight: .semibold))
                        Text(detail(for: selected))
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Copy") { copy(selected) }
                    Button("Show") {
                        NSWorkspace.shared.activateFileViewerSelecting([selected.url])
                    }
                }
                ScrollView {
                    Text(selected.transcript.isEmpty ? "No speech in this session." : selected.transcript)
                        .font(.system(size: 14))
                        .foregroundStyle(selected.transcript.isEmpty ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
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
