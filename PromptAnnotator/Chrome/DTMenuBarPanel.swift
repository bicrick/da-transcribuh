import AppKit
import SwiftUI

/// B/W menu-bar panel matching the menubar-menu mockup.
/// Used inside `MenuBarExtra` with `.menuBarExtraStyle(.window)`.
struct DTMenuBarPanel: View {
    @ObservedObject var session: SessionController
    @ObservedObject var settings: AppSettings
    @Environment(\.dismiss) private var dismiss

    private let panelWidth: CGFloat = 260
    private var shadow: CGFloat { Ink.bevelOffset }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                DTWordmark(size: 11)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, Ink.space3)
            .padding(.vertical, Ink.space2)
            .overlay(alignment: .bottom) {
                Rectangle().fill(Ink.label).frame(height: 1)
            }

            row("open da transcribuh") {
                SettingsPresenter.shared.show()
            }

            hairline

            sessionBlock

            if showsUtilitySection {
                hairline
                utilityBlock
            }

            hairline

            row(settings.appearance.menuLabel) {
                settings.cycleAppearance()
            }

            hairline
            if settings.clipboardHistoryEnabled {
                row("Clipboard history (\(settings.clipboardChord.display))") {
                    ClipboardHistoryController.shared.togglePanel()
                    dismiss()
                }
            }
            // Always listed so a disabled clipboard can still be found and turned on.
            row("Clipboard settings…") {
                SettingsPresenter.shared.show(page: .clipboard)
            }

            hairline

            Text(AppVersion.label)
                .font(Ink.menuBarMetaFont)
                .foregroundStyle(Ink.secondary)
                .padding(.horizontal, Ink.space3)
                .padding(.vertical, Ink.space2)
                .frame(maxWidth: .infinity, alignment: .leading)

            row("quit da transcribuh") {
                NSApp.terminate(nil)
            }
        }
        .frame(width: panelWidth)
        .background(Ink.window)
        .overlay(
            Rectangle()
                .strokeBorder(Ink.label, lineWidth: Ink.stroke)
        )
        .background(alignment: .topLeading) {
            Rectangle()
                .fill(Ink.bevel)
                .offset(x: shadow, y: shadow)
        }
        .padding(.trailing, shadow)
        .padding(.bottom, shadow)
        .background {
            HostWindowAccessor { window in
                polishMenuBarWindow(window)
            }
        }
    }

    // MARK: - Sections

    private var sessionBlock: some View {
        VStack(alignment: .leading, spacing: 0) {
            row(session.toggleTitle, disabled: session.isBusy) {
                session.toggle()
            }

            Text(shortcutHint)
                .font(Ink.menuBarMetaFont)
                .foregroundStyle(Ink.secondary)
                .padding(.horizontal, Ink.space3)
                .padding(.bottom, Ink.space2)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityLabel(shortcutHint)

            if let cancel = settings.cancelChord {
                Text("Cancel: \(cancel.display)")
                    .font(Ink.menuBarMetaFont)
                    .foregroundStyle(Ink.secondary)
                    .padding(.horizontal, Ink.space3)
                    .padding(.bottom, Ink.space2)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if let status = session.menuStatusLine, !status.isEmpty {
                Text(status)
                    .font(Ink.menuBarMetaFont)
                    .foregroundStyle(Ink.secondary)
                    .padding(.horizontal, Ink.space3)
                    .padding(.bottom, Ink.space2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder
    private var utilityBlock: some View {
        if session.canCopyLastAgain {
            row("Copy Last Again", disabled: session.isBusy || session.phase == .recording) {
                session.copyLastAgain()
            }
        }
        if session.lastSessionURL != nil {
            row("Paste Image and Text (\(PasteFollowUp.shortcut))", disabled: session.isBusy || session.phase == .recording) {
                PasteFollowUp.shared.pasteBoth()
            }
            row("Show Last Session in Finder", disabled: session.isBusy) {
                session.revealSession()
            }
        }
    }

    private var showsUtilitySection: Bool {
        session.lastSessionURL != nil || session.canCopyLastAgain
    }

    private var shortcutHint: String {
        let chord = settings.chord.display
        if settings.pushToTalk {
            return "Hold \(chord) to talk"
        }
        return "\(chord) starts and stops"
    }

    private var hairline: some View {
        Rectangle()
            .fill(Ink.label)
            .frame(height: 1)
            .frame(maxWidth: .infinity)
    }

    private func row(
        _ title: String,
        disabled: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        DTMenuRow(title: title, disabled: disabled) {
            guard !disabled else { return }
            action()
            // Theme cycle stays open so the user can click again; other actions dismiss.
            if !title.hasPrefix("theme:") {
                dismiss()
            }
        }
    }

    private func polishMenuBarWindow(_ window: NSWindow) {
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = false
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        if let content = window.contentView {
            content.wantsLayer = true
            content.layer?.cornerRadius = 0
            content.layer?.masksToBounds = false
        }
    }
}

// MARK: - Row

private struct DTMenuRow: View {
    var title: String
    var disabled: Bool
    var action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            InkGlyphString(text: title, size: 13, color: rowForeground)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, Ink.space3)
                .padding(.vertical, Ink.space2)
                .contentShape(Rectangle())
                .background(rowBackground)
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .onHover { hovering = $0 && !disabled }
        .accessibilityLabel(title)
    }

    private var rowForeground: Color {
        if disabled { return Ink.tertiary }
        if hovering { return Ink.onPrimary }
        return Ink.label
    }

    private var rowBackground: Color {
        if disabled { return .clear }
        return hovering ? Ink.primaryFill : .clear
    }
}
