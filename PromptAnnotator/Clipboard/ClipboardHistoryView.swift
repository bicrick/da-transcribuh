import AppKit
import SwiftUI

/// Maccy-structured clipboard panel in Paint ink (Departure Mono, square, 2pt stroke).
struct ClipboardHistoryView: View {
    @ObservedObject var store: ClipboardHistoryStore
    @ObservedObject private var settings = AppSettings.shared
    var onPick: (ClipboardItem, Bool) -> Void
    var onClose: () -> Void
    /// Bumped by the panel on every open. The hosting view is reused, so `onAppear`
    /// does not fire again; this resets search and preselects the first row.
    var openGeneration: UInt64 = 0
    var onOpenPreferences: () -> Void = {
        ClipboardHistoryPanelController.shared.hide(reason: .preferences)
        SettingsPresenter.shared.show(page: .clipboard)
    }
    var onPreview: (ClipboardItem?) -> Void = { _ in }

    @State private var filter = ""
    @State private var selection: UUID?
    @State private var hovered: UUID?
    @State private var previewTask: Task<Void, Never>?
    /// Bumped on each keyboard move so only that move scrolls the selection into view
    /// (hover selection must never scroll the list under the pointer).
    @State private var revealToken = 0
    @State private var revealOnSelect = false
    @FocusState private var searchFocused: Bool
    /// Pointer location at open. Hover only takes the selection once the pointer has
    /// moved, so a panel (or a scroll) sliding under a still pointer can't steal it.
    @State private var openMouse: CGPoint?

    /// Maccy Popup-ish width; Paint chrome around it.
    static let preferredSize = CGSize(width: 450, height: 480)
    private let rowHeight: CGFloat = 22
    /// Linked take rows: a framed collage thumbnail beside two lines of words.
    static let linkedRowHeight: CGFloat = 44
    static let linkedThumbHeight: CGFloat = 36
    static let linkedThumbWidth: CGFloat = 60
    private var imageMaxHeight: CGFloat { CGFloat(settings.clipboardImageHeight) }
    private let hPad: CGFloat = 5

    private var rows: [ClipboardItem] {
        store.orderedForDisplay(filter: filter)
    }


    var body: some View {
        bodyContent.focusEffectDisabled()
    }

    @ViewBuilder private var bodyContent: some View {
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
        .onAppear { resetForOpen() }
        .onChange(of: openGeneration) { _, _ in resetForOpen() }
        .onChange(of: filter) { _, _ in
            PerfProbe.endAfterDisplay("type")
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
            // Same icon + label as the Clipboard folder tab in the main window.
            SettingsPageLabel(page: .clipboard)
                .foregroundStyle(Ink.label)
                .accessibilityAddTraits(.isHeader)
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
            // Order once per body (was three sorts per selection change).
            let all = rows
            let pinnedRows = all.filter(\.pinned)
            let unpinnedRows = all.filter { !$0.pinned }
            // Lazy: only visible rows are built on open. Selection moves one row at a
            // time, and LazyVStack keeps the next row built, so the reveal anchor exists.
            DTScrollView(lazy: true) {
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
        .frame(height: rowHeight(for: item))
        // Short color ease so hover / arrow highlight glides instead of snapping.
        // A color fade is not motion, so it stays on with Reduce Motion.
        .background {
            Rectangle()
                .fill(bg)
                .animation(.easeOut(duration: 0.09), value: bg)
        }
        .background(SelectionRevealAnchor(token: selected && revealOnSelect ? revealToken : nil))
        .contentShape(Rectangle())
        .onTapGesture {
            selection = item.id
            onPick(item, true)
        }
        .onHover { isHovering in
            if isHovering {
                guard pointerMovedSinceOpen() else { return }
                hovered = item.id
                revealOnSelect = false
                selection = item.id
            } else if hovered == item.id {
                hovered = nil
            }
        }
    }

    private func rowHeight(for item: ClipboardItem) -> CGFloat {
        if item.isLinkedSession { return Self.linkedRowHeight }
        return item.kind == .image ? max(rowHeight, imageMaxHeight + 4) : rowHeight
    }

    @ViewBuilder
    private func rowBody(_ item: ClipboardItem, foreground: Color) -> some View {
        switch item.kind {
        case .image:
            ClipboardThumbnail(store: store, item: item, maxHeight: imageMaxHeight)
        case .text where item.isLinkedSession:
            // One take: the collage and its words are one entry.
            HStack(spacing: 8) {
                ClipboardThumbnail(
                    store: store, item: item, maxHeight: Self.linkedThumbHeight - 2,
                    maxWidth: Self.linkedThumbWidth - 2, fitsBox: true
                )
                .frame(width: Self.linkedThumbWidth, height: Self.linkedThumbHeight)
                .background(Ink.window)
                .overlay(Rectangle().strokeBorder(Ink.label, lineWidth: 1))
                Text(String(item.previewLine.prefix(160)))
                    .font(Ink.mono(12))
                    .foregroundStyle(foreground)
                    .lineLimit(2)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Collage and words: \(item.previewLine)")
        case .text where item.isMixed:
            // Text and image from one copy: a small thumbnail keeps the row height.
            HStack(spacing: 6) {
                ClipboardThumbnail(store: store, item: item, maxHeight: rowHeight - 4)
                    .frame(maxWidth: 40, alignment: .leading)
                Text(middleTruncated(item.previewLine))
                    .font(Ink.mono(12))
                    .foregroundStyle(foreground)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
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
                InkGlyphString(text: shortcut, size: 11, color: Ink.secondary)
            }
            .padding(.horizontal, Ink.space3)
            .padding(.vertical, 5)
            .contentShape(Rectangle())
            .retroHover()
        }
        .buttonStyle(.plain)
    }

    // MARK: - Preview scheduling (~400ms)

    private func schedulePreview(for id: UUID?) {
        previewTask?.cancel()
        guard let id, let item = rows.first(where: { $0.id == id }) else {
            onPreview(nil)
            return
        }
        // Preview already up: swap its content in place. Hiding first made it
        // re-slide on every arrow press.
        if ClipboardPreviewPanelController.shared.isShowing {
            onPreview(item)
            return
        }
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

    private func resetForOpen() {
        openMouse = NSEvent.mouseLocation
        hovered = nil
        revealOnSelect = false
        searchFocused = true
        let wasFiltered = !filter.isEmpty
        filter = ""
        selection = rows.first?.id
        // A filter change reselects and schedules the preview itself.
        if !wasFiltered {
            schedulePreview(for: selection)
        }
    }

    private func pointerMovedSinceOpen() -> Bool {
        guard let start = openMouse else { return true }
        let now = NSEvent.mouseLocation
        if hypot(now.x - start.x, now.y - start.y) < 2 { return false }
        openMouse = nil
        return true
    }

    private func moveSelection(_ delta: Int) {
        guard !rows.isEmpty else { return }
        let ids = rows.map(\.id)
        let idx = selection.flatMap { ids.firstIndex(of: $0) } ?? 0
        let next = min(max(idx + delta, 0), ids.count - 1)
        revealOnSelect = true
        revealToken &+= 1
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

// MARK: - Keyboard reveal

/// Scrolls its row into view when `token` changes to a new non-nil value.
/// Keyboard moves only. Eased 0.1s, instant with Reduce Motion.
private struct SelectionRevealAnchor: NSViewRepresentable {
    var token: Int?

    func makeNSView(context: Context) -> AnchorView { AnchorView() }

    func updateNSView(_ view: AnchorView, context: Context) {
        guard let token, token != view.lastToken else { return }
        view.lastToken = token
        DispatchQueue.main.async { view.reveal() }
    }

    final class AnchorView: NSView {
        var lastToken: Int?

        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        func reveal() {
            guard let scroll = enclosingScrollView, let doc = scroll.documentView else { return }
            let clip = scroll.contentView
            let row = convert(bounds, to: doc)
            let visible = clip.bounds
            let pad: CGFloat = 4
            var y = visible.origin.y
            if row.minY < visible.minY {
                y = row.minY - pad
            } else if row.maxY > visible.maxY {
                y = row.maxY - visible.height + pad
            } else {
                return
            }
            let maxY = max(doc.frame.height - visible.height, 0)
            let target = NSPoint(x: visible.origin.x, y: min(max(y, 0), maxY))
            if PanelMotion.reduceMotion {
                clip.setBoundsOrigin(target)
                scroll.reflectScrolledClipView(clip)
                return
            }
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.1
                context.timingFunction = PanelMotion.easeOut
                clip.animator().setBoundsOrigin(target)
            }
            scroll.reflectScrolledClipView(clip)
        }
    }
}

// MARK: - Preview popover

struct ClipboardPreviewPopover: View {
    var item: ClipboardItem
    var image: NSImage?
    /// Final visual height chosen by the panel. Nil while measuring. When set, the
    /// card is exactly this tall and clips its content inside the border, so the
    /// 2pt stroke shows on all four sides even when the body is long.
    var height: CGFloat? = nil

    /// Preview width. 280 truncated copy times ("Oct 22, 2026 at 4:34:4…").
    static let width: CGFloat = 320
    /// Panel caps on the visual card (without the bevel gutter).
    static let minHeight: CGFloat = 120
    static let maxHeight: CGFloat = 520
    /// Image box inside the padding. Mixed items leave room for their text.
    static var contentWidth: CGFloat { width - 2 * Ink.space3 }
    static let imageMaxHeight: CGFloat = 240
    static let mixedImageMaxHeight: CGFloat = 160
    static let textLineLimit = 22
    static let mixedTextLineLimit = 8
    /// Long bodies are cut before layout; the preview shows a few lines anyway.
    static let textCharacterLimit = 2_000

    /// Localized date + time with seconds, e.g. "Oct 22, 2026 at 4:34:42 PM".
    private static let stamp: DateFormatter = {
        let f = DateFormatter()
        f.setLocalizedDateFormatFromTemplate("yMMMdjmmss")
        return f
    }()

    var body: some View {
        bodyContent.focusEffectDisabled()
    }

    @ViewBuilder private var bodyContent: some View {
        VStack(alignment: .leading, spacing: Ink.space2) {
            previewBody
            Rectangle().fill(Ink.hairline).frame(height: 1)
            metaRow("Application:", item.displayApplication)
            metaRow("First copy time:", Self.stamp.string(from: item.firstCopiedAt))
            metaRow("Last copy time:", Self.stamp.string(from: item.lastCopiedAt))
            metaRow("Number of copies:", "\(item.copyCount)")
            if item.isLinkedSession {
                metaRow("Contents:", "collage + words")
                metaRow("Paste:", "picture, then words")
            } else if item.isMixed {
                metaRow("Contents:", "text + image")
            }
            if let w = item.imageWidth, let h = item.imageHeight {
                metaRow("Dimensions:", "\(w) × \(h)")
            }
            Text(item.pinned ? "Press ⌥P to unpin." : "Press ⌥P to pin.")
                .font(Ink.mono(10))
                .foregroundStyle(Ink.secondary)
            InkGlyphString(text: "Press ⌥⌫ to delete.", size: 10, color: Ink.secondary)
        }
        .padding(Ink.space3)
        .frame(width: Self.width, height: height, alignment: .topLeading)
        .clipped()
        .background(Ink.front)
        .overlay(Rectangle().strokeBorder(Ink.label, lineWidth: Ink.stroke))
        .background(
            Rectangle()
                .fill(Ink.bevel)
                .offset(x: Ink.bevelOffset, y: Ink.bevelOffset)
        )
        // Fill the window (card + bevel gutter) from the top-left, so the bevel
        // lands in the gutter instead of the card being centered and cropped.
        .frame(
            width: Self.width + Ink.bevelOffset,
            height: height.map { $0 + Ink.bevelOffset },
            alignment: .topLeading
        )
    }

    @ViewBuilder
    private var previewBody: some View {
        if item.hasImage {
            imageBody
        }
        if item.kind != .image, let text = previewText {
            Text(text)
                .font(Ink.mono(11))
                .foregroundStyle(Ink.label)
                .lineLimit(item.isMixed ? Self.mixedTextLineLimit : Self.textLineLimit)
                .truncationMode(.tail)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
        }
    }

    /// Explicit point size: a `maxWidth`/`maxHeight` frame around a resizable image
    /// left `fittingSize` blind to the image, so the window was sized for the meta
    /// rows only and the picture was cropped away.
    @ViewBuilder
    private var imageBody: some View {
        let box = CGSize(
            width: Self.contentWidth,
            height: item.isMixed ? Self.mixedImageMaxHeight : Self.imageMaxHeight
        )
        let fitted = image.map { ClipboardPreviewLayout.fit($0.size, in: box) } ?? .zero
        if let image, fitted.width > 0, fitted.height > 0 {
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .frame(width: fitted.width, height: fitted.height)
                .overlay(Rectangle().strokeBorder(Ink.hairline, lineWidth: 1))
                .frame(maxWidth: .infinity, alignment: .center)
        } else {
            Text("Image file is missing.")
                .font(Ink.mono(11))
                .foregroundStyle(Ink.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var previewText: String? {
        let raw = item.text ?? item.previewLine
        guard !raw.isEmpty else { return nil }
        if raw.count > Self.textCharacterLimit {
            return String(raw.prefix(Self.textCharacterLimit)) + "…"
        }
        return raw
    }

    private func metaRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(label)
                .font(Ink.mono(10))
                .foregroundStyle(Ink.secondary)
                .fixedSize()
            // Wrap instead of truncating if a value is still too long.
            Text(value)
                .font(Ink.mono(10))
                .foregroundStyle(Ink.label)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// Pure sizing for previews (unit tested).
enum ClipboardPreviewLayout {
    /// Aspect-fit `natural` into `box`, never upscaling, in whole points.
    static func fit(_ natural: CGSize, in box: CGSize) -> CGSize {
        guard natural.width > 0, natural.height > 0, box.width > 0, box.height > 0 else { return .zero }
        let scale = min(box.width / natural.width, box.height / natural.height, 1)
        return CGSize(
            width: max(1, (natural.width * scale).rounded()),
            height: max(1, (natural.height * scale).rounded())
        )
    }

    /// Visual card height from the measured height, inside the panel caps.
    static func cardHeight(measured: CGFloat) -> CGFloat {
        min(max(measured.rounded(.up), ClipboardPreviewPopover.minHeight), ClipboardPreviewPopover.maxHeight)
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
            guard let handlers, let window else { return false }
            // The local monitor is app-wide and outlives orderOut, so only act on
            // keys aimed at the list or its preview. Otherwise Return in Settings
            // could paste the hidden selection.
            let target = event.window
            let ours = target === window
                || (target != nil && target === ClipboardPreviewPanelController.shared.window)
            guard ours, window.isVisible else { return false }
            // Swallow keys during the close fade so they cannot act on a closing list.
            if ClipboardHistoryPanelController.shared.isClosing { return true }
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
            case 125, 126:
                // Arrow -> selection -> committed frame, logged as `dtperf move`.
                PerfProbe.begin("move", event.keyCode == 125 ? "down" : "up")
                handlers.onMove(event.keyCode == 125 ? 1 : -1)
                PerfProbe.endAfterDisplay("move")
                return true
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

/// Row thumbnail: cache hit draws at once; a miss shows the placeholder and decodes off main.
private struct ClipboardThumbnail: View {
    let store: ClipboardHistoryStore
    let item: ClipboardItem
    let maxHeight: CGFloat
    var maxWidth: CGFloat = 120
    /// Fit the whole picture inside `maxWidth` x `maxHeight` (linked rows).
    var fitsBox = false
    @State private var loaded: NSImage?

    var body: some View {
        if fitsBox, let image = loaded ?? store.cachedThumbnail(for: item, maxHeight: maxHeight) {
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .frame(width: maxWidth, height: maxHeight)
        } else if let image = loaded ?? store.cachedThumbnail(for: item, maxHeight: maxHeight) {
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .frame(height: maxHeight)
                .frame(maxWidth: maxWidth, alignment: .leading)
                .clipped()
        } else {
            Rectangle()
                .fill(Ink.fill)
                .frame(width: fitsBox ? maxWidth : 48, height: maxHeight)
                .overlay(Rectangle().strokeBorder(Ink.hairline, lineWidth: 1))
                .task(id: item.imageFileName) {
                    loaded = await store.loadThumbnail(for: item, maxHeight: maxHeight)
                }
        }
    }
}
