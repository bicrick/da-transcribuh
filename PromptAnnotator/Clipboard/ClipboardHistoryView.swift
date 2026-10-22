import AppKit
import SwiftUI

/// Maccy-structured clipboard panel in Paint ink (Departure Mono, square, 2pt stroke).
struct ClipboardHistoryView: View {
    @ObservedObject var store: ClipboardHistoryStore
    @ObservedObject private var settings = AppSettings.shared
    var onPick: (ClipboardItem, Bool) -> Void
    var onClose: () -> Void
    var onOpenPreferences: () -> Void = {
        ClipboardHistoryPanelController.shared.hide()
        SettingsPresenter.shared.show(page: .clipboard)
    }
    var onPreview: (ClipboardItem?) -> Void = { _ in }

    @State private var filter = ""
    @State private var selection: UUID?
    @State private var hovered: UUID?
    @State private var previewTask: Task<Void, Never>?
    @FocusState private var searchFocused: Bool

    /// Maccy Popup-ish width; Paint chrome around it.
    static let preferredSize = CGSize(width: 450, height: 480)
    private let rowHeight: CGFloat = 22
    private var imageMaxHeight: CGFloat { CGFloat(settings.clipboardImageHeight) }
    private let hPad: CGFloat = 5

    private var rows: [ClipboardItem] {
        store.orderedForDisplay(filter: filter)
    }

    private var pinnedRows: [ClipboardItem] { rows.filter(\.pinned) }
    private var unpinnedRows: [ClipboardItem] { rows.filter { !$0.pinned } }

    var body: some View {
        VStack(spacing: 0) {
            if settings.clipboardShowSearchField {
                header
                Rectangle().fill(Ink.label).frame(height: Ink.stroke)
            }
            listBody
            if settings.clipboardShowFooter {
                Rectangle().fill(Ink.hairline).frame(height: 1)
                footer
            }
        }
        .frame(width: Self.preferredSize.width, height: Self.preferredSize.height)
        .background(Ink.front.opacity(0.95))
        .inkDoublePane(cornerRadius: 0, fill: Ink.front.opacity(0.95))
        .onAppear {
            searchFocused = true
            selection = rows.first?.id
            schedulePreview(for: selection)
        }
        .onChange(of: filter) { _, _ in
            selection = rows.first?.id
            schedulePreview(for: selection)
        }
        .onChange(of: selection) { _, id in
            schedulePreview(for: id)
        }
        .onDisappear {
            previewTask?.cancel()
            onPreview(nil)
        }
        .background(KeyboardMonitor(
            onMove: moveSelection,
            onReturn: { option in confirm(paste: !option) },
            onEscape: handleEscape,
            onDigit: pickDigit,
            onPinKey: pickPinKey,
            onPin: pinSelected,
            onDelete: deleteSelected,
            onClear: { store.clearHistory(keepingPinned: true) },
            onPreferences: onOpenPreferences,
            onQuit: { NSApp.terminate(nil) },
            onControlN: { moveSelection(1) },
            onControlP: { moveSelection(-1) }
        ))
    }

    // MARK: - Header (panel title + search)

    private var header: some View {
        HStack(spacing: Ink.space2) {
            Text("clipboard")
                .font(Ink.mono(11))
                .foregroundStyle(Ink.secondary)
                .lineLimit(1)
            Spacer(minLength: 4)
            HStack(spacing: 4) {
                // Drawn — Departure Mono has no ⌕; tofu showed in dark mode.
                ClipboardSearchGlyph()
                    .frame(width: 11, height: 11)
                    .foregroundStyle(Ink.secondary)
                TextField("type to search…", text: $filter)
                    .textFieldStyle(.plain)
                    .font(Ink.mono(12))
                    .foregroundStyle(Ink.label)
                    .focused($searchFocused)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .frame(width: 220, height: 23, alignment: .leading)
            .overlay(Rectangle().strokeBorder(Ink.label, lineWidth: Ink.stroke))
            .background(Ink.window)
        }
        .padding(.horizontal, Ink.space3)
        .padding(.vertical, Ink.space2)
        .background(Ink.fill)
    }

    // MARK: - List

    @ViewBuilder
    private var listBody: some View {
        if rows.isEmpty {
            Text(filter.isEmpty ? "Clipboard history is empty." : "No matches.")
                .font(Ink.mono(12))
                .foregroundStyle(Ink.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            DTScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(Array(pinnedRows.enumerated()), id: \.element.id) { index, item in
                        row(item, shortcutIndex: index)
                    }
                    if !pinnedRows.isEmpty, !unpinnedRows.isEmpty {
                        Rectangle()
                            .fill(Ink.hairline)
                            .frame(height: 1)
                            .padding(.vertical, 2)
                    }
                    ForEach(Array(unpinnedRows.enumerated()), id: \.element.id) { index, item in
                        row(item, shortcutIndex: pinnedRows.count + index)
                    }
                }
                .padding(.vertical, hPad)
            }
        }
    }

    private func row(_ item: ClipboardItem, shortcutIndex: Int) -> some View {
        let selected = item.id == selection
        let hovering = item.id == hovered
        let bg: Color = selected ? Ink.rowSelect : (hovering ? Ink.rowHover : Color.clear)
        // Click pastes + dismisses (Maccy). ⌥Enter keeps open via keyboard path.
        return HStack(spacing: 6) {
            rowBody(item, foreground: Ink.label)
            Spacer(minLength: 0)
            if shortcutIndex < 9 {
                Text(item.pinKey.map { "⌥\($0)" } ?? "⌘\(shortcutIndex + 1)")
                    .font(Ink.mono(10))
                    .foregroundStyle(Ink.secondary.opacity(0.7))
            }
        }
        .padding(.horizontal, hPad + 4)
        .frame(height: item.kind == .image ? max(rowHeight, imageMaxHeight + 4) : rowHeight)
        .background(bg)
        .contentShape(Rectangle())
        .onTapGesture {
            selection = item.id
            onPick(item, true)
        }
        .onHover { isHovering in
            if isHovering {
                hovered = item.id
                selection = item.id
            } else if hovered == item.id {
                hovered = nil
            }
        }
    }

    @ViewBuilder
    private func rowBody(_ item: ClipboardItem, foreground: Color) -> some View {
        switch item.kind {
        case .image:
            if let image = store.image(for: item) {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .frame(height: imageMaxHeight)
                    .frame(maxWidth: 120, alignment: .leading)
                    .clipped()
            } else {
                Rectangle()
                    .fill(Ink.fill)
                    .frame(width: 48, height: imageMaxHeight)
                    .overlay(Rectangle().strokeBorder(Ink.hairline, lineWidth: 1))
            }
        case .text, .fileURL:
            Text(middleTruncated(item.previewLine))
                .font(Ink.mono(12))
                .foregroundStyle(foreground)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Footer (Maccy Clear / Preferences / Quit)

    private var footer: some View {
        VStack(spacing: 0) {
            footerRow("Clear", shortcut: "⌥⌘⌫") {
                store.clearHistory(keepingPinned: true)
            }
            footerRow("Preferences…", shortcut: "⌘,") {
                onOpenPreferences()
            }
            footerRow("Quit", shortcut: "⌘Q") {
                NSApp.terminate(nil)
            }
        }
        .background(Ink.fill)
    }

    private func footerRow(_ title: String, shortcut: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(title)
                    .font(Ink.mono(12))
                    .foregroundStyle(Ink.label)
                Spacer(minLength: 0)
                Text(shortcut)
                    .font(Ink.mono(11))
                    .foregroundStyle(Ink.secondary)
            }
            .padding(.horizontal, Ink.space3)
            .padding(.vertical, 5)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Preview scheduling (~400ms)

    private func schedulePreview(for id: UUID?) {
        previewTask?.cancel()
        onPreview(nil)
        guard let id, let item = rows.first(where: { $0.id == id }) else { return }
        let delay = UInt64(max(0, settings.clipboardPreviewDelayMs)) * 1_000_000
        previewTask = Task { @MainActor in
            if delay > 0 {
                try? await Task.sleep(nanoseconds: delay)
            }
            guard !Task.isCancelled, selection == id else { return }
            onPreview(item)
        }
    }

    // MARK: - Helpers

    private func middleTruncated(_ text: String, limit: Int = 48) -> String {
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

    /// ⌥{pinKey} pastes the pinned item that advertises that shortcut.
    private func pickPinKey(_ key: String) -> Bool {
        let needle = key.uppercased()
        guard let item = rows.first(where: { $0.pinKey?.uppercased() == needle }) else {
            return false
        }
        onPick(item, true)
        return true
    }

    private func pinSelected() {
        guard let id = selection else { return }
        store.togglePin(id)
        schedulePreview(for: selection)
    }

    private func deleteSelected() {
        guard let id = selection else { return }
        store.delete(id)
        selection = rows.first?.id
        schedulePreview(for: selection)
    }

    private func handleEscape() {
        if !filter.isEmpty {
            filter = ""
        } else {
            onClose()
        }
    }
}

// MARK: - Preview popover

struct ClipboardPreviewPopover: View {
    var item: ClipboardItem
    var image: NSImage?

    private static let stamp: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .medium
        return f
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: Ink.space2) {
            previewBody
            Rectangle().fill(Ink.hairline).frame(height: 1)
            metaRow("Application:", item.displayApplication)
            metaRow("First copy time:", Self.stamp.string(from: item.firstCopiedAt))
            metaRow("Last copy time:", Self.stamp.string(from: item.lastCopiedAt))
            metaRow("Number of copies:", "\(item.copyCount)")
            if let w = item.imageWidth, let h = item.imageHeight {
                metaRow("Dimensions:", "\(w) × \(h)")
            }
            Text(item.pinned ? "Press ⌥P to unpin." : "Press ⌥P to pin.")
                .font(Ink.mono(10))
                .foregroundStyle(Ink.secondary)
            Text("Press ⌥⌫ to delete.")
                .font(Ink.mono(10))
                .foregroundStyle(Ink.secondary)
        }
        .padding(Ink.space3)
        .frame(width: 280, alignment: .leading)
        .background(Ink.front)
        .overlay(Rectangle().strokeBorder(Ink.label, lineWidth: Ink.stroke))
        .background(
            Rectangle()
                .fill(Ink.bevel)
                .offset(x: Ink.bevelOffset, y: Ink.bevelOffset)
        )
    }

    @ViewBuilder
    private var previewBody: some View {
        switch item.kind {
        case .image:
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: 248, maxHeight: 180)
                    .frame(maxWidth: .infinity)
            }
        case .text, .fileURL:
            Text(item.text ?? item.previewLine)
                .font(Ink.mono(11))
                .foregroundStyle(Ink.label)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
        }
    }

    private func metaRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(label)
                .font(Ink.mono(10))
                .foregroundStyle(Ink.secondary)
            Text(value)
                .font(Ink.mono(10))
                .foregroundStyle(Ink.label)
                .lineLimit(2)
        }
    }
}

// MARK: - Key monitor

private struct KeyboardMonitor: NSViewRepresentable {
    var onMove: (Int) -> Void
    var onReturn: (_ option: Bool) -> Void
    var onEscape: () -> Void
    var onDigit: (Int) -> Void
    /// Returns true when an ⌥{char} pin shortcut was consumed.
    var onPinKey: (String) -> Bool
    var onPin: () -> Void
    var onDelete: () -> Void
    var onClear: () -> Void
    var onPreferences: () -> Void
    var onQuit: () -> Void
    var onControlN: () -> Void
    var onControlP: () -> Void

    func makeNSView(context: Context) -> MonitorView {
        let view = MonitorView()
        view.apply(self)
        return view
    }

    func updateNSView(_ nsView: MonitorView, context: Context) {
        nsView.apply(self)
    }

    final class MonitorView: NSView {
        var handlers: KeyboardMonitor?
        private var monitor: Any?

        func apply(_ handlers: KeyboardMonitor) {
            self.handlers = handlers
        }

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
            guard let handlers else { return false }
            let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            // ⌃N / ⌃P
            if mods.contains(.control), !mods.contains(.command), !mods.contains(.option),
               let ch = event.charactersIgnoringModifiers?.lowercased() {
                if ch == "n" { handlers.onControlN(); return true }
                if ch == "p" { handlers.onControlP(); return true }
            }
            if mods.contains(.command), mods.contains(.option), !mods.contains(.shift),
               (event.keyCode == 51 || event.keyCode == 117) {
                handlers.onClear()
                return true
            }
            if mods.contains(.command), !mods.contains(.option), !mods.contains(.shift),
               event.charactersIgnoringModifiers == "," {
                handlers.onPreferences()
                return true
            }
            if mods.contains(.command), !mods.contains(.option), !mods.contains(.shift),
               event.charactersIgnoringModifiers?.lowercased() == "q" {
                handlers.onQuit()
                return true
            }
            if mods.contains(.command), !mods.contains(.option), !mods.contains(.shift),
               let ch = event.charactersIgnoringModifiers, let n = Int(ch), (1...9).contains(n) {
                handlers.onDigit(n)
                return true
            }
            if mods.contains(.option), !mods.contains(.command),
               event.charactersIgnoringModifiers?.lowercased() == "p" {
                handlers.onPin()
                return true
            }
            if mods.contains(.option), (event.keyCode == 51 || event.keyCode == 117) {
                handlers.onDelete()
                return true
            }
            // Custom pin keys (⌥B etc.) after reserved ⌥P / ⌥⌫.
            if mods.contains(.option), !mods.contains(.command),
               let ch = event.charactersIgnoringModifiers, ch.count == 1,
               handlers.onPinKey(ch) {
                return true
            }
            switch event.keyCode {
            case 125: handlers.onMove(1); return true
            case 126: handlers.onMove(-1); return true
            case 36, 76:
                handlers.onReturn(mods.contains(.option))
                return true
            case 53:
                handlers.onEscape()
                return true
            default:
                return false
            }
        }
    }
}

/// Paint-style magnifying glass (circle + handle). Avoids missing-glyph tofu
/// from `⌕`, which Departure Mono does not include.
private struct ClipboardSearchGlyph: View {
    var body: some View {
        Canvas { context, size in
            let stroke = max(Ink.stroke * 0.75, 1.2)
            let inset = stroke / 2
            let glass = min(size.width, size.height) * 0.62
            let origin = CGPoint(x: inset, y: inset)
            let circle = CGRect(x: origin.x, y: origin.y, width: glass, height: glass)
            var path = Path(ellipseIn: circle)
            let handleStart = CGPoint(x: circle.maxX - stroke * 0.2, y: circle.maxY - stroke * 0.2)
            let handleEnd = CGPoint(x: size.width - inset, y: size.height - inset)
            path.move(to: handleStart)
            path.addLine(to: handleEnd)
            context.stroke(path, with: .foreground, lineWidth: stroke)
        }
        .accessibilityHidden(true)
    }
}
