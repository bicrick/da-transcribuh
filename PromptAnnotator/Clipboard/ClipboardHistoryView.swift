import AppKit
import SwiftUI

/// Paint-styled clipboard history list: search, rows, ⌘1–9, pin/delete.
struct ClipboardHistoryView: View {
    @ObservedObject var store: ClipboardHistoryStore
    var onPick: (ClipboardItem, Bool) -> Void
    var onClose: () -> Void

    @State private var filter = ""
    @State private var selection: UUID?
    @FocusState private var searchFocused: Bool

    static let preferredSize = CGSize(width: 360, height: 420)

    private var rows: [ClipboardItem] {
        store.orderedForDisplay(filter: filter)
    }

    var body: some View {
        VStack(spacing: 0) {
            searchField
            Rectangle().fill(Ink.label).frame(height: Ink.stroke)
            if rows.isEmpty {
                Text(filter.isEmpty ? "Clipboard history is empty." : "No matches.")
                    .font(Ink.mono(12))
                    .foregroundStyle(Ink.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(rows.enumerated()), id: \.element.id) { index, item in
                            row(item, index: index)
                            Rectangle().fill(Ink.hairline).frame(height: 1)
                        }
                    }
                }
            }
            footer
        }
        .frame(width: Self.preferredSize.width, height: Self.preferredSize.height)
        .background(Ink.front)
        .inkDoublePane(cornerRadius: Ink.cardRadius, fill: Ink.front)
        .onAppear {
            searchFocused = true
            selection = rows.first?.id
        }
        .onChange(of: filter) { _, _ in
            selection = rows.first?.id
        }
        .background(KeyboardMonitor(
            onMove: moveSelection,
            onReturn: { option in confirm(paste: !option) },
            onEscape: onClose,
            onDigit: pickDigit,
            onPin: pinSelected,
            onDelete: deleteSelected
        ))
    }

    private var searchField: some View {
        HStack(spacing: Ink.space2) {
            Text("⌕")
                .font(Ink.mono(12))
                .foregroundStyle(Ink.secondary)
            TextField("Filter…", text: $filter)
                .textFieldStyle(.plain)
                .font(Ink.mono(12))
                .foregroundStyle(Ink.label)
                .focused($searchFocused)
        }
        .padding(.horizontal, Ink.space3)
        .padding(.vertical, Ink.space2)
        .background(Ink.fill)
    }

    private var footer: some View {
        HStack(spacing: Ink.space3) {
            Text("↑↓ Enter · ⌥Enter copy · ⌥P pin · ⌥⌫ del · Esc")
                .font(Ink.mono(9))
                .foregroundStyle(Ink.secondary)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Ink.space3)
        .padding(.vertical, Ink.space2)
        .background(Ink.fill)
        .overlay(alignment: .top) {
            Rectangle().fill(Ink.hairline).frame(height: 1)
        }
    }

    private func row(_ item: ClipboardItem, index: Int) -> some View {
        let selected = item.id == selection
        return Button {
            selection = item.id
            onPick(item, true)
        } label: {
            HStack(spacing: Ink.space2) {
                if index < 9 {
                    Text("⌘\(index + 1)")
                        .font(Ink.mono(10))
                        .foregroundStyle(Ink.secondary)
                        .frame(width: 28, alignment: .leading)
                } else {
                    Color.clear.frame(width: 28)
                }
                thumbnail(item)
                Text(middleTruncated(item.previewLine))
                    .font(Ink.mono(12))
                    .foregroundStyle(Ink.label)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if item.pinned {
                    Text("Pinned")
                        .font(Ink.mono(9))
                        .foregroundStyle(Ink.secondary)
                }
                Text(sourceTag(item.source))
                    .font(Ink.mono(9))
                    .foregroundStyle(Ink.secondary)
            }
            .padding(.horizontal, Ink.space3)
            .padding(.vertical, Ink.space2)
            .background(selected ? Ink.fill : Ink.front)
            .overlay(
                Rectangle()
                    .strokeBorder(selected ? Ink.label : Color.clear, lineWidth: Ink.stroke)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func thumbnail(_ item: ClipboardItem) -> some View {
        switch item.kind {
        case .image:
            if let image = store.image(for: item) {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 28, height: 28)
                    .clipped()
                    .overlay(Rectangle().strokeBorder(Ink.label, lineWidth: 1))
            } else {
                Rectangle()
                    .fill(Ink.fill)
                    .frame(width: 28, height: 28)
                    .overlay(Rectangle().strokeBorder(Ink.label, lineWidth: 1))
            }
        case .fileURL:
            Text("⌘")
                .font(Ink.mono(11))
                .frame(width: 28, height: 28)
                .overlay(Rectangle().strokeBorder(Ink.label, lineWidth: 1))
        case .text:
            Text("T")
                .font(Ink.mono(11))
                .frame(width: 28, height: 28)
                .overlay(Rectangle().strokeBorder(Ink.label, lineWidth: 1))
        }
    }

    private func sourceTag(_ source: ClipboardItemSource) -> String {
        switch source {
        case .pasteboard: return ""
        case .transcript: return "words"
        case .screenshot: return "tile"
        }
    }

    private func middleTruncated(_ text: String, limit: Int = 42) -> String {
        guard text.count > limit else { return text }
        let head = limit / 2 - 1
        let tail = limit - head - 1
        return String(text.prefix(head)) + "…" + String(text.suffix(tail))
    }

    private func moveSelection(_ delta: Int) {
        guard !rows.isEmpty else { return }
        let ids = rows.map(\.id)
        let idx = selection.flatMap { ids.firstIndex(of: $0) } ?? 0
        let next = min(max(idx + delta, 0), ids.count - 1)
        selection = ids[next]
    }

    private func confirm(paste: Bool) {
        guard let id = selection, let item = rows.first(where: { $0.id == id }) else { return }
        onPick(item, paste)
    }

    private func pickDigit(_ n: Int) {
        guard n >= 1, n <= 9, rows.count >= n else { return }
        onPick(rows[n - 1], true)
    }

    private func pinSelected() {
        guard let id = selection else { return }
        store.togglePin(id)
    }

    private func deleteSelected() {
        guard let id = selection else { return }
        store.delete(id)
        selection = rows.first?.id
    }
}

// MARK: - Key monitor (local to panel)

private struct KeyboardMonitor: NSViewRepresentable {
    var onMove: (Int) -> Void
    var onReturn: (_ option: Bool) -> Void
    var onEscape: () -> Void
    var onDigit: (Int) -> Void
    var onPin: () -> Void
    var onDelete: () -> Void

    func makeNSView(context: Context) -> MonitorView {
        let view = MonitorView()
        view.onMove = onMove
        view.onReturn = onReturn
        view.onEscape = onEscape
        view.onDigit = onDigit
        view.onPin = onPin
        view.onDelete = onDelete
        return view
    }

    func updateNSView(_ nsView: MonitorView, context: Context) {
        nsView.onMove = onMove
        nsView.onReturn = onReturn
        nsView.onEscape = onEscape
        nsView.onDigit = onDigit
        nsView.onPin = onPin
        nsView.onDelete = onDelete
    }

    final class MonitorView: NSView {
        var onMove: ((Int) -> Void)?
        var onReturn: ((Bool) -> Void)?
        var onEscape: (() -> Void)?
        var onDigit: ((Int) -> Void)?
        var onPin: (() -> Void)?
        var onDelete: (() -> Void)?
        private var monitor: Any?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if monitor == nil {
                monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                    self?.handle(event) == true ? nil : event
                }
            }
        }

        deinit {
            if let monitor {
                NSEvent.removeMonitor(monitor)
            }
        }

        private func handle(_ event: NSEvent) -> Bool {
            let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            if mods.contains(.command), !mods.contains(.option), !mods.contains(.shift),
               let ch = event.charactersIgnoringModifiers, let n = Int(ch), (1...9).contains(n) {
                onDigit?(n)
                return true
            }
            if mods.contains(.option), !mods.contains(.command),
               event.charactersIgnoringModifiers?.lowercased() == "p" {
                onPin?()
                return true
            }
            if mods.contains(.option), (event.keyCode == 51 || event.keyCode == 117) {
                onDelete?()
                return true
            }
            switch event.keyCode {
            case 125: onMove?(1); return true
            case 126: onMove?(-1); return true
            case 36, 76:
                onReturn?(mods.contains(.option))
                return true
            case 53:
                onEscape?()
                return true
            default:
                return false
            }
        }
    }
}
