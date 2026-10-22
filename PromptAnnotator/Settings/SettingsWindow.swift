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
        VStack(spacing: 0) {
            DTTitleStrip()

            NavigationSplitView {
                VStack(spacing: 0) {
                    SettingsSidebar(selection: $page)
                    sidebarFooter
                }
                .background(Ink.sidebar)
                .navigationSplitViewColumnWidth(
                    min: Ink.sidebarWidth - 8,
                    ideal: Ink.sidebarWidth,
                    max: Ink.sidebarWidth + 16
                )
            } detail: {
                VStack(spacing: 0) {
                    detail
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .toolbar(.hidden, for: .automatic)
                    DTStatusBar(cells: statusCells, trailing: AppVersion.label)
                }
                .background(Ink.window)
            }
            .navigationSplitViewStyle(.balanced)
        }
        .tint(Ink.label)
        .background(Ink.window)
        // Draw under the (hidden) system titlebar so our strip owns the top edge.
        .ignoresSafeArea(.container, edges: .top)
        .onAppear {
            SettingsPresenter.shared.applyChrome()
            reload()
        }
        .onReceive(NotificationCenter.default.publisher(for: .promptAnnotatorSettingsShown)) { _ in
            reload()
            permissions.refresh()
            SettingsPresenter.shared.applyChrome()
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

    private var statusCells: [String] {
        var cells: [String] = []
        let state: String = {
            if !session.statusText.isEmpty { return session.statusText.lowercased() }
            if let hint = session.pasteReadyHint, !hint.isEmpty { return "ready to paste" }
            return "idle"
        }()
        cells.append("■ \(state)")
        cells.append(settings.speechModel)
        let n = sessions.count
        cells.append("\(n) session\(n == 1 ? "" : "s")")
        cells.append(settings.chord.display)
        return cells
    }

    private var sidebarFooter: some View {
        VStack(spacing: 4) {
            Image("AppMark")
                .resizable()
                .interpolation(.high)
                .frame(width: 28, height: 28)
                .overlay(
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .strokeBorder(Ink.label, lineWidth: 1)
                )
            Text(AppVersion.label)
                .font(.system(size: 9))
                .foregroundStyle(Ink.secondary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 8)
        .padding(.vertical, 10)
        .overlay(alignment: .top) {
            Rectangle().fill(Ink.hairline).frame(height: 1)
        }
    }

    private func reload() {
        sessions = SessionLibrary.load()
    }
}

/// Single-column tool-palette sidebar: square tiles (icon above label), selected = inverted.
struct SettingsSidebar: View {
    @Binding var selection: SettingsPage

    var body: some View {
        ScrollView {
            VStack(alignment: .center, spacing: 2) {
                ForEach(SettingsPage.sidebarSections, id: \.title) { section in
                    Text(section.title.uppercased())
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Ink.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 2)
                        .padding(.top, 12)
                        .padding(.bottom, 6)

                    VStack(spacing: 6) {
                        ForEach(section.pages) { item in
                            toolTile(item)
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)
            .padding(.bottom, 8)
            .frame(maxWidth: .infinity, alignment: .top)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Settings")
    }

    private func toolTile(_ item: SettingsPage) -> some View {
        let selected = selection == item
        return Button {
            selection = item
        } label: {
            VStack(spacing: 6) {
                Image(systemName: item.symbol)
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(selected ? Ink.onAccent : Ink.label)
                Text(item.title)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(selected ? Ink.onAccent : Ink.label)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            .frame(width: Ink.sidebarTileSize, height: Ink.sidebarTileSize)
            .background(
                (selected ? Ink.label : Ink.window),
                in: RoundedRectangle(cornerRadius: Ink.sidebarRowRadius, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Ink.sidebarRowRadius, style: .continuous)
                    .strokeBorder(Ink.label, lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
        .accessibilityLabel(item.title)
        .accessibilityAddTraits(selected ? [.isSelected, .isButton] : .isButton)
    }
}

@MainActor
final class SettingsPresenter {
    static let shared = SettingsPresenter()

    private var window: NSWindow?
    private let shownKey = "home.shown"

    /// Exposed for custom traffic lights (performClose / miniaturize / zoom).
    var attachedWindow: NSWindow? { window }

    func showOnFirstLaunch() {
        guard !UserDefaults.standard.bool(forKey: shownKey) else { return }
        UserDefaults.standard.set(true, forKey: shownKey)
        show()
    }

    func show() {
        let window = ensure()
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        applyChrome()
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
        window.title = "da transcribuh"
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.titlebarSeparatorStyle = .none
        window.isReleasedWhenClosed = false
        window.backgroundColor = Ink.windowNSColor
        window.contentView = host
        window.setContentSize(NSSize(width: 880, height: 640))
        window.minSize = NSSize(width: 760, height: 560)
        window.center()
        self.window = window
        applyChrome()
        return window
    }

    var isKey: Bool {
        window?.isKeyWindow == true
    }

    func applyChrome() {
        guard let window else { return }
        window.level = AppSettings.shared.keepWindowOnTop ? .floating : .normal
        window.backgroundColor = Ink.windowNSColor
        // Keep closable / miniaturizable in the style mask so ⌘W / ⌘M still work
        // even though the stock buttons are hidden behind our custom lights.
        DTSystemTrafficLights.hide(on: window)
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
