import AppKit
import SwiftUI

extension Notification.Name {
    static let promptAnnotatorSettingsShown = Notification.Name("promptAnnotatorSettingsShown")
    static let promptAnnotatorSessionsChanged = Notification.Name("promptAnnotatorSessionsChanged")
}

struct SettingsRoot: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var session: SessionController
    @StateObject private var permissions = PermissionModel()
    @State private var page: SettingsPage = .home
    @State private var sessions: [SessionSummary] = []

    var body: some View {
        NavigationSplitView {
            VStack(spacing: 0) {
                SettingsSidebar(selection: $page)
                footer
            }
            .background(Ink.sidebar)
            .navigationSplitViewColumnWidth(
                min: Ink.sidebarWidth - 24,
                ideal: Ink.sidebarWidth,
                max: Ink.sidebarWidth + 20
            )
        } detail: {
            detail
                // Avoid an empty detail toolbar band stacking on top of pageTop.
                .toolbar(.hidden, for: .automatic)
        }
        .navigationSplitViewStyle(.balanced)
        .tint(Ink.accent)
        .background(Ink.window)
        .onAppear(perform: reload)
        .onReceive(NotificationCenter.default.publisher(for: .promptAnnotatorSettingsShown)) { _ in
            reload()
            permissions.refresh()
        }
        .onReceive(NotificationCenter.default.publisher(for: .promptAnnotatorSessionsChanged)) { _ in
            reload()
        }
    }

    @ViewBuilder
    private var detail: some View {
        switch page {
        case .home:
            HomePage(session: session, settings: settings, permissions: permissions, sessions: sessions)
        case .history:
            HistoryPage(sessions: sessions, reload: reload)
        case .recording:
            RecordingPage(settings: settings, session: session)
        case .configuration:
            ConfigurationPage(settings: settings)
        case .sound:
            SoundPage(settings: settings)
        case .model:
            ModelPage()
        case .performance:
            PerformancePage()
        }
    }

    private var footer: some View {
        HStack(spacing: 8) {
            AppLogo(side: 22)
            VStack(alignment: .leading, spacing: 0) {
                Text("Mutter")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Ink.label)
                Text(AppVersion.label)
                    .font(.system(size: 10))
                    .foregroundStyle(Ink.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, SettingsMetrics.sidebarFooterPadding)
        .padding(.vertical, 10)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Ink.hairline)
                .frame(height: 1)
        }
    }

    private func reload() {
        sessions = SessionLibrary.load()
    }
}

/// Custom sidebar so selection uses Ink tint (List + `.sidebar` forces the system accent pill).
struct SettingsSidebar: View {
    @Binding var selection: SettingsPage

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(SettingsPage.sidebarSections, id: \.title) { section in
                    Text(section.title)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Ink.tertiary)
                        .padding(.horizontal, 10)
                        .padding(.top, 16)
                        .padding(.bottom, 6)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    ForEach(section.pages) { item in
                        sidebarRow(item)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)
            .padding(.bottom, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Settings")
    }

    private func sidebarRow(_ item: SettingsPage) -> some View {
        let selected = selection == item
        return Button {
            selection = item
        } label: {
            HStack(spacing: 9) {
                Image(systemName: item.symbol)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(selected ? Ink.accent : Ink.secondary)
                    .frame(width: 18, alignment: .center)
                Text(item.title)
                    .font(.system(size: 13, weight: selected ? .semibold : .regular))
                    .foregroundStyle(selected ? Ink.accent : Ink.label)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .frame(height: 30)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: Ink.sidebarRowRadius, style: .continuous)
                    .fill(selected ? Ink.sidebarSelection : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(item.title)
        .accessibilityAddTraits(selected ? [.isSelected, .isButton] : .isButton)
    }
}

@MainActor
final class SettingsPresenter {
    static let shared = SettingsPresenter()

    private var window: NSWindow?
    private let shownKey = "home.shown"

    func showOnFirstLaunch() {
        guard !UserDefaults.standard.bool(forKey: shownKey) else { return }
        UserDefaults.standard.set(true, forKey: shownKey)
        show()
    }

    func show() {
        let window = ensure()
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        NotificationCenter.default.post(name: .promptAnnotatorSettingsShown, object: nil)
    }

    private func ensure() -> NSWindow {
        if let window { return window }
        let root = SettingsRoot()
            .environmentObject(AppSettings.shared)
            .environmentObject(SessionController.shared)
        let host = NSHostingView(rootView: root)
        host.autoresizingMask = [.width, .height]
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 880, height: 600),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "Mutter"
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.titlebarSeparatorStyle = .none
        window.isReleasedWhenClosed = false
        window.backgroundColor = Ink.windowNSColor
        window.contentView = host
        window.setContentSize(NSSize(width: 880, height: 600))
        window.minSize = NSSize(width: 760, height: 520)
        window.center()
        self.window = window
        applyChrome()
        return window
    }

    var isKey: Bool {
        window?.isKeyWindow == true
    }

    func applyChrome() {
        window?.level = AppSettings.shared.keepWindowOnTop ? .floating : .normal
        window?.backgroundColor = Ink.windowNSColor
    }
}

enum ReturnKey {
    static func post() {
        guard let source = CGEventSource(stateID: .hidSystemState) else { return }
        let down = CGEvent(keyboardEventSource: source, virtualKey: 0x24, keyDown: true)
        let up = CGEvent(keyboardEventSource: source, virtualKey: 0x24, keyDown: false)
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
    }
}
