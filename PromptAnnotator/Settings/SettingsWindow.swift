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

            SettingsFolderTabs(selection: $page)

            VStack(spacing: 0) {
                detail
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .toolbar(.hidden, for: .automatic)
                DTStatusBar(
                    cells: statusCells,
                    trailing: AppVersion.label,
                    recording: session.phase == .recording
                )
            }
            .background(Ink.front)
            // Content sits under the selected folder tab (no gap / no double hairline).
            .zIndex(0)
        }
        .tint(Ink.label)
        .background(Ink.window)
        .preferredColorScheme(settings.appearance.preferredColorScheme)
        // Draw under the (hidden) system titlebar so our strip owns the top edge.
        .ignoresSafeArea(.container, edges: .top)
        .onAppear {
            settings.appearance.applyToApp()
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
        .focusable()
        .onMoveCommand(perform: handleMove)
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
        cells.append(state)
        cells.append(settings.speechModel)
        let n = sessions.count
        cells.append("\(n) session\(n == 1 ? "" : "s")")
        cells.append(settings.chord.display)
        return cells
    }

    private func handleMove(_ direction: MoveCommandDirection) {
        let pages = SettingsPage.tabOrder
        guard let index = pages.firstIndex(of: page) else { return }
        switch direction {
        case .left where index > 0:
            page = pages[index - 1]
        case .right where index < pages.count - 1:
            page = pages[index + 1]
        default:
            break
        }
    }

    private func reload() {
        sessions = SessionLibrary.load()
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
            contentRect: NSRect(x: 0, y: 0, width: 980, height: 600),
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
        window.setContentSize(NSSize(width: 1040, height: 700))
        // Wide enough for all seven folder tabs without truncation.
        window.minSize = NSSize(width: 980, height: 600)
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
