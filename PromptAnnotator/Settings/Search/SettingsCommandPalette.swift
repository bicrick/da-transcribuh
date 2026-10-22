import AppKit
import SwiftUI

/// Cmd+K command palette — Departure Mono, double-pane white/graphite card.
struct SettingsCommandPalette: View {
    @Binding var isPresented: Bool
    var sessions: [SessionSummary]
    var modelTitles: [String]
    var onSelect: (SettingsSearchHit) -> Void

    @State private var query = ""
    @State private var selection = 0
    @FocusState private var fieldFocused: Bool

    private var hits: [SettingsSearchHit] {
        SettingsSearch.search(query: query, sessions: sessions, modelTitles: modelTitles)
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.28)
                .ignoresSafeArea()
                .onTapGesture { dismiss() }

            VStack(spacing: 0) {
                inputRow
                Rectangle().fill(Ink.hairline).frame(height: 1)
                results
            }
            .frame(width: 520)
            .background(Ink.front)
            .overlay(Rectangle().strokeBorder(Ink.label, lineWidth: Ink.stroke))
            .background(
                Rectangle()
                    .fill(Ink.bevel)
                    .offset(x: Ink.bevelOffset, y: Ink.bevelOffset)
            )
            .padding(.bottom, Ink.bevelOffset)
            .padding(.trailing, Ink.bevelOffset)
            .offset(y: -36)
        }
        .onAppear {
            query = ""
            selection = 0
            fieldFocused = true
        }
        .onChange(of: query) { _, _ in
            selection = 0
        }
        .onExitCommand { dismiss() }
        .background(arrowKeys)
    }

    private var arrowKeys: some View {
        Group {
            Button("Up") { moveSelection(-1) }
                .keyboardShortcut(.upArrow, modifiers: [])
            Button("Down") { moveSelection(1) }
                .keyboardShortcut(.downArrow, modifiers: [])
        }
        .opacity(0)
        .frame(width: 0, height: 0)
        .accessibilityHidden(true)
    }

    private var inputRow: some View {
        HStack(spacing: Ink.space2) {
            Text("⌕")
                .font(Ink.labelFont)
                .foregroundStyle(Ink.secondary)
            TextField("Search settings, history, models…", text: $query)
                .textFieldStyle(.plain)
                .font(Ink.mono(14))
                .foregroundStyle(Ink.label)
                .focused($fieldFocused)
                .onSubmit { activateSelection() }
            Text("esc")
                .font(Ink.mono(10))
                .foregroundStyle(Ink.tertiary)
        }
        .padding(.horizontal, Ink.space4)
        .padding(.vertical, Ink.space3)
    }

    private var results: some View {
        let rows = hits
        return Group {
            if rows.isEmpty {
                Text(query.isEmpty ? "Type to search" : "No matches")
                    .font(Ink.captionFont)
                    .foregroundStyle(Ink.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(Ink.space4)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            ForEach(Array(rows.enumerated()), id: \.element.id) { index, hit in
                                resultRow(hit, index: index, selected: index == selection)
                                    .id(hit.id)
                            }
                        }
                    }
                    .frame(maxHeight: 320)
                    .onChange(of: selection) { _, newValue in
                        guard rows.indices.contains(newValue) else { return }
                        withAnimation(.easeOut(duration: 0.12)) {
                            proxy.scrollTo(rows[newValue].id, anchor: .center)
                        }
                    }
                }
            }
        }
        .background(Ink.front)
    }

    private func resultRow(_ hit: SettingsSearchHit, index: Int, selected: Bool) -> some View {
        Button {
            selection = index
            activateSelection()
        } label: {
            HStack(alignment: .top, spacing: Ink.space3) {
                Text(kindGlyph(hit.kind))
                    .font(Ink.mono(11))
                    .foregroundStyle(Ink.secondary)
                    .frame(width: 18, alignment: .center)
                    .padding(.top, 2)
                VStack(alignment: .leading, spacing: 2) {
                    Text(hit.title)
                        .font(Ink.labelFont)
                        .foregroundStyle(Ink.label)
                        .lineLimit(1)
                    if let snippet = hit.snippet, let range = hit.matchRange {
                        HighlightedSnippet(text: snippet, range: range)
                    } else {
                        Text(hit.subtitle)
                            .font(Ink.captionFont)
                            .foregroundStyle(Ink.secondary)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
                Text(hit.page.title)
                    .font(Ink.mono(10))
                    .foregroundStyle(Ink.tertiary)
            }
            .padding(.horizontal, Ink.space4)
            .padding(.vertical, Ink.space2 + 2)
            .background(selected ? Ink.fill : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func kindGlyph(_ kind: SettingsSearchHit.Kind) -> String {
        switch kind {
        case .page: return "▤"
        case .setting: return "·"
        case .history: return "◷"
        case .model: return "∿"
        }
    }

    private func activateSelection() {
        let rows = hits
        guard rows.indices.contains(selection) else { return }
        let hit = rows[selection]
        isPresented = false
        onSelect(hit)
    }

    private func dismiss() {
        isPresented = false
    }

    /// Arrow keys while the field is focused.
    func moveSelection(_ delta: Int) {
        let count = hits.count
        guard count > 0 else { return }
        selection = (selection + delta + count) % count
    }
}

/// Flat paint-yellow highlight over the matched span.
struct HighlightedSnippet: View {
    var text: String
    var range: NSRange

    var body: some View {
        highlighted
            .font(Ink.captionFont)
            .foregroundStyle(Ink.secondary)
            .lineLimit(2)
            .multilineTextAlignment(.leading)
    }

    private var highlighted: Text {
        guard let swift = Range(range, in: text) else {
            return Text(text)
        }
        var attributed = AttributedString(text)
        if let attrRange = Range(swift, in: attributed) {
            attributed[attrRange].backgroundColor = Ink.paintYellow
            attributed[attrRange].foregroundColor = Ink.paintBlack
        }
        return Text(attributed)
    }
}

/// Quiet discoverability chip — tab row trailing.
/// Square face + hard ink bevel (same Paint language as folder tabs / bento cells).
struct SettingsSearchAffordance: View {
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Text("⌕")
                    .font(Ink.mono(11))
                Text("⌘K")
                    .font(Ink.mono(10))
            }
            .foregroundStyle(Ink.secondary)
            .padding(.horizontal, Ink.space2)
            .padding(.vertical, 4)
            .background(Ink.fill)
            .overlay(Rectangle().strokeBorder(Ink.controlBorder, lineWidth: Ink.stroke))
            .background(alignment: .topTrailing) {
                Rectangle()
                    .fill(Ink.bevel)
                    .frame(width: Ink.bevelOffset)
                    .offset(x: Ink.bevelOffset)
            }
            .padding(.trailing, Ink.bevelOffset)
        }
        .buttonStyle(.plain)
        .help("Search settings (⌘K)")
        .accessibilityLabel("Search settings")
    }
}
