import AppKit
import SwiftUI

extension Notification.Name {
    static let promptAnnotatorSettingsShown = Notification.Name("promptAnnotatorSettingsShown")
}

struct SettingsRoot: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var session: SessionController
    @StateObject private var permissions = PermissionModel()
    @State private var page: SettingsPage? = .home
    @State private var sessions: [SessionSummary] = []

    var body: some View {
        NavigationSplitView {
            VStack(spacing: 0) {
                List(selection: $page) {
                    ForEach(SettingsPage.allCases) { item in
                        Label(item.title, systemImage: item.symbol)
                            .tag(item)
                    }
                }
                .listStyle(.sidebar)
                footer
            }
            .navigationSplitViewColumnWidth(min: 188, ideal: 200, max: 220)
        } detail: {
            switch page ?? .home {
            case .home:
                HomePage(session: session, settings: settings, permissions: permissions, sessions: sessions)
            case .sessions:
                SessionsPage(sessions: sessions, reload: reload)
            case .recording:
                RecordingPage(settings: settings, session: session)
            case .sound:
                SoundPage(settings: settings)
            case .model:
                ModelPage()
            }
        }
        .navigationSplitViewStyle(.balanced)
        .onAppear(perform: reload)
        .onReceive(NotificationCenter.default.publisher(for: .promptAnnotatorSettingsShown)) { _ in
            reload()
            permissions.refresh()
        }
    }

    private var footer: some View {
        HStack(spacing: 8) {
            AppLogo(side: 22)
            VStack(alignment: .leading, spacing: 0) {
                Text("Prompt Annotator")
                    .font(.system(size: 11, weight: .semibold))
                Text("Menu bar")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
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
        window.title = "Prompt Annotator"
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.titlebarSeparatorStyle = .none
        window.isReleasedWhenClosed = false
        window.backgroundColor = .windowBackgroundColor
        window.contentView = host
        window.setContentSize(NSSize(width: 880, height: 600))
        window.minSize = NSSize(width: 760, height: 520)
        window.center()
        self.window = window
        return window
    }
}
