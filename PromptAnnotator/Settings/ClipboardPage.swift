import AppKit
import SwiftUI

/// Clipboard preferences in Paint ink sections. Every control is a Paint
/// component (no stock Stepper / Slider / radio Picker).
struct ClipboardPage: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject private var store = ClipboardHistoryStore.shared
    @State private var ignoreDraft = ""
    @State private var confirmClear = false
    @State private var message: String?
    @State private var captureChord = false
    /// Folder size, measured off the main thread. Was a synchronous directory
    /// scan inside `body` that re-ran on every store publish.
    @State private var diskBytes: Int64?

    var body: some View {
        SettingsPageStack(
            title: "Clipboard",
            subtitle: "What gets saved, how the panel looks, and how it pastes."
        ) {
            if let message {
                Text(message)
                    .font(Ink.captionFont)
                    .foregroundStyle(Ink.secondary)
            }
            SettingsSection(title: "General") { generalCard }
            SettingsSection(title: "Storage") { storageCard }
            SettingsSection(title: "Appearance") { appearanceCard }
            SettingsSection(title: "Pins", footer: "Pin from the panel with ⌥P, then edit titles here.") { pinsCard }
            SettingsSection(title: "Ignore") { ignoreCard }
            SettingsSection(title: "Advanced") { advancedCard }
        }
        .task(id: diskSignature) {
            let folder = store.storageFolder
            let bytes = await Task.detached(priority: .utility) {
                ClipboardHistoryStore.diskUsageBytes(at: folder)
            }.value
            diskBytes = bytes
        }
    }

    /// Re-measure disk use only when the history actually changes.
    private var diskSignature: String {
        "\(store.items.count)-\(store.items.first?.id.uuidString ?? "")"
    }

    private var diskUsageText: String {
        guard let diskBytes else { return "On disk: measuring…" }
        return "On disk: \(ByteCountFormatter.string(fromByteCount: diskBytes, countStyle: .file))"
    }

    private var generalCard: some View {
        InkCard {
            VStack(alignment: .leading, spacing: 0) {
                InkToggleRow(
                    title: "Enable clipboard history",
                    detail: "\(settings.clipboardChord.display) opens the panel.",
                    isOn: Binding(
                        get: { settings.clipboardHistoryEnabled },
                        set: { settings.setClipboardHistoryEnabled($0) }
                    )
                )
                InkDivider(leading: 0)
                InkSettingRow(
                    title: "Open shortcut",
                    detail: "Default ⇧⌘C. Shift is allowed for clipboard."
                ) {
                    InkShortcutRecorder(
                        keys: settings.clipboardChord.keycaps,
                        listening: captureChord
                    ) {
                        captureChord = true
                        message = nil
                    }
                }
                HStack {
                    Spacer()
                    Button {
                        captureChord = false
                        message = settings.setClipboardChord(.clipboardDefault)
                            ? nil
                            : "macOS would not register the shortcut."
                    } label: {
                        InkGlyphString(text: "Reset to ⇧⌘C", size: 11)
                    }
                    .buttonStyle(InkSecondaryButtonStyle())
                }
                .padding(.horizontal, Ink.rowHPad)
                .padding(.bottom, Ink.rowVPad)
                InkDivider(leading: 0)
                InkToggleRow(
                    title: "Paste automatically",
                    detail: "Off: choosing a row copies it and closes the panel. On: it also pastes into the frontmost app.",
                    isOn: Binding(
                        get: { settings.clipboardPasteAutomatically },
                        set: { settings.setClipboardPasteAutomatically($0) }
                    )
                )
                InkDivider(leading: 0)
                InkToggleRow(
                    title: "Paste without formatting",
                    detail: "Stage plain text when pasting history text.",
                    isOn: Binding(
                        get: { settings.clipboardPasteWithoutFormatting },
                        set: { settings.setClipboardPasteWithoutFormatting($0) }
                    )
                )
            }
        }
        .background(clipboardChordCapture)
    }

    private var clipboardChordCapture: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .onAppear {}
            .background(
                KeyCaptureView(isActive: captureChord) { event in
                    captureChord = false
                    if event.keyCode == 53 {
                        message = nil
                        return
                    }
                    let chord = HotkeyChord(event: event)
                    if let rejection = chord.rejection(allowingShift: true) {
                        message = rejection
                        return
                    }
                    message = settings.setClipboardChord(chord)
                        ? nil
                        : "Could not register."
                }
            )
    }

    private var storageCard: some View {
        InkCard {
            VStack(alignment: .leading, spacing: 0) {
                InkToggleRow(
                    title: "Save files",
                    detail: "Capture file URLs from the pasteboard.",
                    isOn: Binding(
                        get: { settings.clipboardSaveFiles },
                        set: { settings.setClipboardSaveFiles($0) }
                    )
                )
                InkDivider(leading: 0)
                InkToggleRow(
                    title: "Save images",
                    detail: "Capture image pasteboard types.",
                    isOn: Binding(
                        get: { settings.clipboardSaveImages },
                        set: { settings.setClipboardSaveImages($0) }
                    )
                )
                InkDivider(leading: 0)
                InkToggleRow(
                    title: "Save text",
                    detail: "Capture plain text and RTF as text.",
                    isOn: Binding(
                        get: { settings.clipboardSaveText },
                        set: { settings.setClipboardSaveText($0) }
                    )
                )
                InkDivider(leading: 0)
                InkSettingRow(
                    title: "History size",
                    detail: "\(diskUsageText). Pinned items are kept."
                ) {
                    InkStepper(
                        title: "History size",
                        value: Binding(
                            get: { settings.clipboardHistoryLimit },
                            set: { settings.setClipboardHistoryLimit($0) }
                        ),
                        range: 20...500,
                        step: 10,
                        format: { "\($0) items" },
                        valueWidth: 84
                    )
                }
                InkDivider(leading: 0)
                InkSettingRow(title: "Sort by", detail: "Order of unpinned items in the panel.") {
                    InkRadioGroup(
                        title: "Sort by",
                        selection: Binding(
                            get: { settings.clipboardSortMode },
                            set: { settings.setClipboardSortMode($0) }
                        ),
                        options: ClipboardSortMode.allCases.map { ($0, $0.title) }
                    )
                    .frame(width: 200, alignment: .leading)
                }
            }
        }
    }

    private var appearanceCard: some View {
        InkCard {
            VStack(alignment: .leading, spacing: 0) {
                InkSettingRow(title: "Popup position", detail: "Where the panel opens.") {
                    InkRadioGroup(
                        title: "Popup position",
                        selection: Binding(
                            get: { settings.clipboardPopupPosition },
                            set: { settings.setClipboardPopupPosition($0) }
                        ),
                        options: ClipboardPopupPosition.allCases.map { ($0, $0.title) }
                    )
                    .frame(width: 200, alignment: .leading)
                }
                InkDivider(leading: 0)
                InkSettingRow(title: "Pinned section", detail: "Pins sit above or below history.") {
                    InkRadioGroup(
                        title: "Pinned section",
                        selection: Binding(
                            get: { settings.clipboardPinEdge },
                            set: { settings.setClipboardPinEdge($0) }
                        ),
                        options: ClipboardPinEdge.allCases.map { ($0, $0.title) }
                    )
                    .frame(width: 200, alignment: .leading)
                }
                InkDivider(leading: 0)
                InkSettingRow(title: "Image height", detail: "Max height of image thumbnails.") {
                    InkValueSlider(
                        title: "Image height",
                        value: Binding(
                            get: { settings.clipboardImageHeight },
                            set: { settings.setClipboardImageHeight($0) }
                        ),
                        range: 24...120,
                        step: 1,
                        format: { "\(Int($0)) pt" }
                    )
                }
                InkDivider(leading: 0)
                InkSettingRow(title: "Preview delay", detail: "Wait before the hover preview shows.") {
                    InkStepper(
                        title: "Preview delay",
                        value: Binding(
                            get: { settings.clipboardPreviewDelayMs },
                            set: { settings.setClipboardPreviewDelayMs($0) }
                        ),
                        range: 0...2000,
                        step: 50,
                        format: { "\($0) ms" },
                        valueWidth: 84
                    )
                }
                InkDivider(leading: 0)
                InkToggleRow(
                    title: "Show search field",
                    detail: "Header search above the list.",
                    isOn: Binding(
                        get: { settings.clipboardShowSearchField },
                        set: { settings.setClipboardShowSearchField($0) }
                    )
                )
                InkDivider(leading: 0)
                InkToggleRow(
                    title: "Show footer",
                    detail: "Clear / Preferences… / Quit.",
                    isOn: Binding(
                        get: { settings.clipboardShowFooter },
                        set: { settings.setClipboardShowFooter($0) }
                    )
                )
            }
        }
    }

    private var pinsCard: some View {
        InkCard {
            let pinned = store.items.filter(\.pinned)
            if pinned.isEmpty {
                Text("No pinned items yet.")
                    .font(Ink.captionFont)
                    .foregroundStyle(Ink.secondary)
                    .padding(Ink.rowHPad)
                    .padding(.vertical, Ink.rowVPad)
            } else {
                VStack(alignment: .leading, spacing: Ink.space2) {
                    ForEach(pinned) { item in
                        PinEditorRow(item: item) { title, key in
                            store.updatePinMetadata(id: item.id, title: title, key: key)
                        }
                    }
                }
                .padding(Ink.rowHPad)
                .padding(.vertical, Ink.rowVPad)
            }
        }
    }

    private var ignoreCard: some View {
        InkCard {
            VStack(alignment: .leading, spacing: 0) {
                InkToggleRow(
                    title: "Ignore concealed and password types",
                    detail: "Skip transient / confidential pasteboard marks.",
                    isOn: Binding(
                        get: { settings.clipboardIgnoreConcealed },
                        set: { settings.setClipboardIgnoreConcealed($0) }
                    )
                )
                InkDivider(leading: 0)
                VStack(alignment: .leading, spacing: Ink.space2) {
                    Text("Ignored apps")
                        .font(Ink.rowTitleFont)
                        .foregroundStyle(Ink.label)
                    Text("Copies from these bundle IDs are never saved.")
                        .font(Ink.captionFont)
                        .foregroundStyle(Ink.secondary)
                    ForEach(settings.clipboardIgnoredApps, id: \.self) { id in
                        HStack {
                            Text(id)
                                .font(Ink.optionFont)
                                .foregroundStyle(Ink.label)
                                .lineLimit(1)
                            Spacer()
                            Button("Remove") { settings.removeClipboardIgnoredApp(id) }
                                .buttonStyle(InkSecondaryButtonStyle())
                                .accessibilityLabel("Remove \(id)")
                        }
                    }
                    HStack(spacing: Ink.space2) {
                        TextField("com.example.app", text: $ignoreDraft)
                            .textFieldStyle(.plain)
                            .font(Ink.optionFont)
                            .foregroundStyle(Ink.label)
                            .inkFieldStyle()
                            .onSubmit(addIgnoredApp)
                        Button("Add", action: addIgnoredApp)
                            .buttonStyle(InkSecondaryButtonStyle())
                            .disabled(ignoreDraft.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
                .padding(Ink.rowHPad)
                .padding(.vertical, Ink.rowVPad)
            }
        }
    }

    private func addIgnoredApp() {
        let trimmed = ignoreDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        settings.addClipboardIgnoredApp(trimmed)
        ignoreDraft = ""
    }

    private var advancedCard: some View {
        InkCard {
            VStack(alignment: .leading, spacing: 0) {
                InkToggleRow(
                    title: "Pause capture",
                    detail: "Keep history; stop watching the pasteboard.",
                    isOn: Binding(
                        get: { settings.clipboardCapturePaused },
                        set: { settings.setClipboardCapturePaused($0) }
                    )
                )
                InkDivider(leading: 0)
                InkToggleRow(
                    title: "Clear history on quit",
                    detail: "Wipe stored items when the app exits.",
                    isOn: Binding(
                        get: { settings.clipboardClearOnQuit },
                        set: { settings.setClipboardClearOnQuit($0) }
                    )
                )
                InkDivider(leading: 0)
                InkToggleRow(
                    title: "Also clear system clipboard",
                    detail: "When clearing history, empty the general pasteboard.",
                    isOn: Binding(
                        get: { settings.clipboardClearSystemClipboard },
                        set: { settings.setClipboardClearSystemClipboard($0) }
                    )
                )
                InkDivider(leading: 0)
                HStack {
                    Button(confirmClear ? "Click again to confirm" : "Clear history") {
                        if confirmClear {
                            store.clearHistoryFully(clearSystem: settings.clipboardClearSystemClipboard)
                            confirmClear = false
                            message = "History cleared."
                        } else {
                            confirmClear = true
                        }
                    }
                    .buttonStyle(InkSecondaryButtonStyle())
                    Spacer()
                }
                .padding(Ink.rowHPad)
                .padding(.vertical, Ink.rowVPad)
            }
        }
    }
}

private struct PinEditorRow: View {
    let item: ClipboardItem
    var onSave: (String?, String?) -> Void
    @State private var title: String = ""
    @State private var key: String = ""

    var body: some View {
        HStack(spacing: Ink.space2) {
            Text(item.previewLine)
                .font(Ink.optionFont)
                .foregroundStyle(Ink.label)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            TextField("Title", text: $title)
                .textFieldStyle(.plain)
                .font(Ink.optionFont)
                .foregroundStyle(Ink.label)
                .frame(width: 140)
                .inkFieldStyle()
            TextField("Key", text: $key)
                .textFieldStyle(.plain)
                .font(Ink.optionFont)
                .foregroundStyle(Ink.label)
                .multilineTextAlignment(.center)
                .frame(width: 28)
                .inkFieldStyle()
                .accessibilityLabel("Pin key")
            Button("Save") { onSave(title, key) }
                .buttonStyle(InkSecondaryButtonStyle())
        }
        .onAppear {
            title = item.pinTitle ?? ""
            key = item.pinKey ?? ""
        }
    }
}

/// Minimal key capture host for rebinding the clipboard chord on this page.
private struct KeyCaptureView: NSViewRepresentable {
    var isActive: Bool
    var onEvent: (NSEvent) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = Monitor()
        view.onEvent = onEvent
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        guard let view = nsView as? Monitor else { return }
        view.onEvent = onEvent
        view.setActive(isActive)
    }

    final class Monitor: NSView {
        var onEvent: ((NSEvent) -> Void)?
        private var monitor: Any?

        func setActive(_ active: Bool) {
            if active {
                guard monitor == nil else { return }
                monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                    self?.onEvent?(event)
                    return nil
                }
            } else if let monitor {
                NSEvent.removeMonitor(monitor)
                self.monitor = nil
            }
        }

        deinit {
            if let monitor { NSEvent.removeMonitor(monitor) }
        }
    }
}
