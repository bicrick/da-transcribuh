import AppKit
import SwiftUI

/// B/W menu-bar panel matching the menubar-menu mockup.
/// Used inside `MenuBarExtra` with `.menuBarExtraStyle(.window)`.
struct DTMenuBarPanel: View {
    @ObservedObject var session: SessionController
    @ObservedObject var settings: AppSettings
    @Environment(\.dismiss) private var dismiss

    private let panelWidth: CGFloat = 252
    private var shadow: CGFloat { Ink.menuBarShadow }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
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

            Text(AppVersion.label)
                .font(.system(size: 11))
                .foregroundStyle(Ink.secondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .frame(maxWidth: .infinity, alignment: .leading)

            row("quit da transcribuh") {
                NSApp.terminate(nil)
            }
        }
        .frame(width: panelWidth)
        .background(Ink.window)
        .overlay(
            Rectangle()
                .strokeBorder(Ink.label, lineWidth: 1)
        )
        .background(alignment: .topLeading) {
            Rectangle()
                .fill(Ink.label)
                .offset(x: shadow, y: shadow)
        }
        .padding(.trailing, shadow)
        .padding(.bottom, shadow)
        .background {
            HostWindowAccessor { window in
                polishMenuBarWindow(window)
            }
        }
        .preferredColorScheme(nil)
    }

    // MARK: - Sections

    private var sessionBlock: some View {
        VStack(alignment: .leading, spacing: 0) {
            row(session.toggleTitle, disabled: session.isBusy) {
                session.toggle()
            }

            Text(shortcutHint)
                .font(.system(size: 11))
                .foregroundStyle(Ink.secondary)
                .padding(.horizontal, 12)
                .padding(.bottom, 6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityLabel(shortcutHint)

            if let cancel = settings.cancelChord {
                Text("Cancel: \(cancel.display)")
                    .font(.system(size: 11))
                    .foregroundStyle(Ink.secondary)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 6)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if let status = session.menuStatusLine, !status.isEmpty {
                Text(status)
                    .font(.system(size: 11))
                    .foregroundStyle(Ink.secondary)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 8)
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
            dismiss()
        }
    }

    /// Clear the system panel chrome so our 1px border + hard shadow read cleanly.
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
            Text(title)
                .font(.system(size: 13))
                .foregroundStyle(rowForeground)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
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
        if hovering { return Ink.onAccent }
        return Ink.label
    }

    private var rowBackground: Color {
        if disabled { return .clear }
        return hovering ? Ink.label : .clear
    }
}
