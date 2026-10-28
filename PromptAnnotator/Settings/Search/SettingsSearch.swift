import Foundation
import SwiftUI

/// Pulse-highlight target after jumping from the command palette.
private struct SettingsHighlightKey: EnvironmentKey {
    static let defaultValue: String? = nil
}

extension EnvironmentValues {
    var settingsHighlightTitle: String? {
        get { self[SettingsHighlightKey.self] }
        set { self[SettingsHighlightKey.self] = newValue }
    }
}

/// One hit in the Settings command palette / jump list.
struct SettingsSearchHit: Identifiable, Equatable {
    enum Kind: String, Equatable {
        case page
        case setting
        case history
        case model
    }

    var id: String
    var kind: Kind
    var title: String
    var subtitle: String
    var page: SettingsPage
    /// Optional setting title to pulse-highlight after jumping.
    var highlightTitle: String? = nil
    /// History session id when kind == .history.
    var sessionID: String? = nil
    /// Precomputed snippet with the match span (UTF-16 NSRange into `snippet`).
    var snippet: String? = nil
    var matchRange: NSRange? = nil
}

/// Static + dynamic Settings search index.
enum SettingsSearch {
    /// Pages and individual settings (stable catalog).
    static let catalog: [SettingsSearchHit] = {
        var hits: [SettingsSearchHit] = []
        for page in SettingsPage.tabOrder {
            hits.append(
                SettingsSearchHit(
                    id: "page.\(page.rawValue)",
                    kind: .page,
                    title: page.pageTitle,
                    subtitle: "Go to \(page.pageTitle)",
                    page: page
                )
            )
        }
        hits += settingHits
        return hits
    }()

    private static let settingHits: [SettingsSearchHit] = [
        // Home
        hit("home.permissions", .home, "Permissions", "Screen Recording, Microphone, Accessibility"),
        hit("home.model", .home, "Speech model", "WhisperKit or Parakeet on this Mac"),
        hit("home.first", .home, "First take", "Start a session"),
        hit("home.shortcut", .home, "Change recording shortcut", "Edit Start/Stop chord on Home"),
        // Appearance (theme + former Recording page)
        hit("app.theme", .appearance, "Theme", "System, Light, Dark"),
        hit("app.style", .appearance, "Recording window", "Default, Compact, Minimal, Hidden"),
        hit("app.tool", .appearance, "Annotation tool", "Shift-drag defaults"),
        hit("app.color", .appearance, "Annotation color", "Ink swatch defaults"),
        // Models
        hit("model.engine", .model, "Engine", "On this Mac or server"),
        hit("model.builtin", .model, "Built-in models", "WhisperKit Fast/Balanced or Parakeet Highest"),
        hit("model.custom", .model, "Your models", "Core ML folders"),
        hit("model.hf", .model, "Add from Hugging Face", "Bring your own model"),
        hit("model.server", .model, "Server", "OpenAI-compatible final pass"),
        // General
        hit("gen.start", .configuration, "Start and stop", "Session shortcut"),
        hit("gen.cancel", .configuration, "Cancel recording", "Discard shortcut"),
        hit("clip.enable", .clipboard, "Clipboard history", "Enable pasteboard history panel"),
        hit("clip.chord", .clipboard, "Clipboard shortcut", "Open history near the pointer (⇧⌘C)"),
        hit("clip.limit", .clipboard, "Clipboard history limit", "Max items; pinned survive Clear"),
        hit("clip.storage", .clipboard, "Clipboard storage", "Save files, images, text"),
        hit("clip.ignore", .clipboard, "Clipboard ignore", "Ignored apps and concealed types"),
        hit("clip.advanced", .clipboard, "Clipboard advanced", "Pause capture, clear on quit"),
        hit("gen.ptt", .configuration, "Push to talk", "Hold to record"),
        hit("gen.shotkey", .configuration, "Screenshot key", "Hold for the crosshair (Shift)"),
        hit("gen.drawkey", .configuration, "Annotate key", "Hold to draw (Control)"),
        hit("gen.login", .configuration, "Launch at login", "Open at login"),
        hit("gen.updates", .configuration, "Updates", "Check for a new build"),
        hit("gen.top", .configuration, "Keep this window above others", "Floating Settings"),
        hit("gen.dock", .configuration, "Show in the Dock", "Dock icon"),
        hit("gen.log", .configuration, "Write errors to a log", "Error log"),
        hit("gen.silence", .configuration, "Stop after silence", "Auto-stop"),
        hit("gen.max", .configuration, "Maximum session", "Time limit"),
        hit("gen.norm", .configuration, "Normalize quiet speech", "Raise quiet takes"),
        hit("gen.folder", .configuration, "Sessions folder", "Where takes are saved"),
        hit("gen.paste", .configuration, "Paste when the session ends", "Auto-paste"),
        hit("gen.return", .configuration, "Press Return when Shift is held", "Synthetic return"),
        hit("gen.caps", .configuration, "Capitalize the pasted transcript", "Leading capital"),
        // Sound
        hit("snd.input", .sound, "Input", "Microphone"),
        hit("snd.boost", .sound, "Raise the input level", "Input gain"),
        hit("snd.tones", .sound, "Play session tones", "Start/stop sounds"),
        hit("snd.volume", .sound, "Volume", "Tone volume"),
        // Perf
        hit("perf.app", .performance, "App memory", "Resident memory for this process"),
        hit("perf.mac", .performance, "This Mac", "Physical memory and processors"),
        hit("perf.model", .performance, "Model on disk", "WhisperKit weights on disk"),
    ]

    private static func hit(_ id: String, _ page: SettingsPage, _ title: String, _ subtitle: String) -> SettingsSearchHit {
        SettingsSearchHit(
            id: id,
            kind: .setting,
            title: title,
            subtitle: subtitle,
            page: page,
            highlightTitle: title
        )
    }

    /// Ranked matches across catalog + history + models.
    static func search(
        query: String,
        sessions: [SessionSummary],
        modelTitles: [String],
        limit: Int = 24
    ) -> [SettingsSearchHit] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else {
            return Array(catalog.prefix(12))
        }

        var scored: [(Int, SettingsSearchHit)] = []

        for hit in catalog {
            if let score = score(haystacks: [hit.title, hit.subtitle], needle: needle) {
                scored.append((score, hit))
            }
        }

        for title in modelTitles {
            if let score = score(haystacks: [title, "model"], needle: needle) {
                scored.append((
                    score,
                    SettingsSearchHit(
                        id: "model.\(title)",
                        kind: .model,
                        title: title,
                        subtitle: "Speech model",
                        page: .model,
                        highlightTitle: title
                    )
                ))
            }
        }

        for session in sessions {
            if let match = HistorySearch.firstMatch(in: session, query: needle) {
                scored.append((
                    match.score,
                    SettingsSearchHit(
                        id: "history.\(session.id)",
                        kind: .history,
                        title: session.preview.isEmpty ? session.id : session.preview,
                        subtitle: "History",
                        page: .history,
                        sessionID: session.id,
                        snippet: match.snippet,
                        matchRange: match.range
                    )
                ))
            }
        }

        scored.sort { lhs, rhs in
            if lhs.0 != rhs.0 { return lhs.0 > rhs.0 }
            return lhs.1.title.localizedCaseInsensitiveCompare(rhs.1.title) == .orderedAscending
        }
        return scored.prefix(limit).map(\.1)
    }

    /// Higher is better. Title prefix beats title contains beats subtitle.
    static func score(haystacks: [String], needle: String) -> Int? {
        let n = needle.lowercased()
        var best: Int?
        for (index, raw) in haystacks.enumerated() {
            let h = raw.lowercased()
            guard h.contains(n) else { continue }
            let base = index == 0 ? 100 : 40
            let points: Int
            if h == n {
                points = base + 50
            } else if h.hasPrefix(n) {
                points = base + 30
            } else {
                points = base
            }
            best = max(best ?? 0, points)
        }
        return best
    }
}
