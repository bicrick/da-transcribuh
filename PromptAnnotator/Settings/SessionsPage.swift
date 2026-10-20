import AppKit
import SwiftUI

struct SessionsPage: View {
    var sessions: [SessionSummary]
    var reload: () -> Void

    var body: some View {
        SettingsPageStack(title: "Sessions") {
            if sessions.isEmpty {
                SettingsCard {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("No sessions yet")
                            .font(.system(size: 13, weight: .semibold))
                        Text("Stop a recording and it will show up here, with the tile sheet and the transcript.")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                    .padding(14)
                }
            } else {
                SettingsCard {
                    ForEach(Array(sessions.enumerated()), id: \.element.id) { index, session in
                        if index > 0 {
                            SettingsDivider()
                        }
                        row(session)
                    }
                }
            }
        }
        .onAppear(perform: reload)
    }

    private func row(_ session: SessionSummary) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title(for: session))
                    .font(.system(size: 13, weight: .semibold))
                Text(detail(for: session))
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Button("Copy") {
                copySession(at: session.url)
            }
            Button("Show") {
                NSWorkspace.shared.activateFileViewerSelecting([session.url])
            }
        }
        .padding(12)
    }

    private func title(for session: SessionSummary) -> String {
        if let started = session.started {
            return started.formatted(date: .abbreviated, time: .shortened)
        }
        return session.id
    }

    private func detail(for session: SessionSummary) -> String {
        let tileNoun = session.tiles == 1 ? "tile" : "tiles"
        let wordNoun = session.words == 1 ? "word" : "words"
        return "\(session.tiles) \(tileNoun) · \(session.words) \(wordNoun) · \(TimeFormat.clock(session.duration))"
    }

    private func copySession(at url: URL) {
        let image = NSImage(contentsOf: url.appendingPathComponent("sheet.png"))
        let notes = (try? String(contentsOf: url.appendingPathComponent("session.md"), encoding: .utf8)) ?? ""
        SessionClipboard.copy(image: image, transcript: notes)
    }
}
