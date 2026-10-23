import AppKit
import SwiftUI

extension Notification.Name {
    static let promptAnnotatorSettingsShown = Notification.Name("promptAnnotatorSettingsShown")
    static let promptAnnotatorSessionsChanged = Notification.Name("promptAnnotatorSessionsChanged")
    static let promptAnnotatorSettingsSelectPage = Notification.Name("promptAnnotatorSettingsSelectPage")
}

struct SettingsRoot: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var session: SessionController
    @StateObject private var permissions = PermissionModel()
    @State private var page: SettingsPage = .home
    @State private var sessions: [SessionSummary] = []
    /// Reference box: stamping a reload must not re-render the window.
    @State private var lastReloadAt = ReloadStamp()
    @State private var showPalette = false
    @State private var highlightTitle: String? = nil
    @State private var historyQuery = ""
    @State private var focusHistorySearch = false
    @State private var selectHistoryID: String? = nil

    var body: some View {
        let _ = PerfSuite.count("settingsRoot")
        ZStack {
            VStack(spacing: 0) {
                DTTitleStrip()

                SettingsFolderTabs(selection: timedPage) {
                    showPalette = true
                }

                VStack(spacing: 0) {
                    detail
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .toolbar(.hidden, for: .automatic)
                        .environment(\.settingsHighlightTitle, highlightTitle)
                    DTStatusBar(
                        cells: statusCells,
                        trailing: AppVersion.label,
                        recording: session.phase == .recording
                    )
                }
                .background(Ink.front)
                .zIndex(0)
            }

            if showPalette {
                SettingsCommandPalette(
                    isPresented: $showPalette,
                    sessions: sessions,
                    modelTitles: modelTitles,
                    onSelect: handleSearchHit
                )
                .transition(.opacity)
                .zIndex(20)
            }
        }
        .tint(Ink.label)
        .background(Ink.window)
        // Appearance is driven only by NSApp.appearance (AppSettings.setAppearance).
        // Do not also apply preferredColorScheme — double source of truth flickers chrome.
        .ignoresSafeArea(.container, edges: .top)
        .onAppear {
            settings.appearance.applyToApp()
            SettingsPresenter.shared.applyChrome()
            reload()
            if let pending = SettingsPresenter.shared.takePendingPage() {
                page = pending
            }
            PerfHarness.runTabCycle { next in timedPage.wrappedValue = next }
            SnapshotHarness.run { next in timedPage.wrappedValue = next }
        }
        .onReceive(NotificationCenter.default.publisher(for: .promptAnnotatorSettingsShown)) { _ in
            // First open fires onAppear and this notification back to back.
            // Skip the second load (it decoded the library twice per open).
            reloadUnlessRecent(0.5)
            permissions.refresh()
            SettingsPresenter.shared.applyChrome()
        }
        .onReceive(NotificationCenter.default.publisher(for: .promptAnnotatorSettingsSelectPage)) { note in
            _ = SettingsPresenter.shared.takePendingPage()
            if let raw = note.object as? String, let next = SettingsPage(rawValue: raw) {
                page = next
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .promptAnnotatorSessionsChanged)) { _ in
            reload()
        }
        .focusable(!showPalette)
        .onMoveCommand { direction in
            guard !showPalette else { return }
            handleMove(direction)
        }
        .background(shortcutButtons)
        .animation(.easeOut(duration: 0.12), value: showPalette)
    }

    /// Invisible buttons so ⌘K / ⌘F register even when a text field isn't focused.
    private var shortcutButtons: some View {
        Group {
            Button("Search") { showPalette = true }
                .keyboardShortcut("k", modifiers: .command)
            Button("Find") {
                if page == .history {
                    focusHistorySearch = true
                } else {
                    showPalette = true
                }
            }
            .keyboardShortcut("f", modifiers: .command)
        }
        .opacity(0)
        .frame(width: 0, height: 0)
        .accessibilityHidden(true)
    }

    /// Tab selection that times each switch (PerfProbe "tab").
    private var timedPage: Binding<SettingsPage> {
        Binding(
            get: { page },
            set: { next in
                guard next != page else { return }
                PerfProbe.begin("tab", next.rawValue)
                page = next
            }
        )
    }

    @ViewBuilder
    private var detail: some View {
        pageView
            .onAppear { PerfProbe.endAfterCommit("tab") }
            .id(page)
    }

    @ViewBuilder
    private var pageView: some View {
        switch page {
        case .home:
            HomePage(
                session: session,
                settings: settings,
                permissions: permissions,
                sessions: sessions,
                onOpenHistory: { id in
                    page = .history
                    selectHistoryID = id
                },
                onOpenModels: { page = .model },
                onOpenSound: { page = .sound }
            )
        case .history:
            HistoryPage(
                sessions: sessions,
                reload: reload,
                query: $historyQuery,
                focusSearch: $focusHistorySearch,
                selectedID: $selectHistoryID
            )
        case .appearance:
            AppearancePage(settings: settings, session: session)
        case .clipboard:
            ClipboardPage(settings: settings)
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

    private var modelTitles: [String] {
        var titles = SpeechModelChoice.all.map(\.title)
        titles += settings.customModels.map(\.name)
        titles.append(settings.speechModel)
        return titles
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

    private func handleSearchHit(_ hit: SettingsSearchHit) {
        page = hit.page
        switch hit.kind {
        case .history:
            if let id = hit.sessionID {
                selectHistoryID = id
                if let snippetNeedle = hit.snippet {
                    // Prefer the original query's match — use preview/id fallback.
                    historyQuery = extractNeedle(from: hit) ?? historyQuery
                }
                focusHistorySearch = false
            }
            // Enter on history: copy that session.
            if let id = hit.sessionID, let session = sessions.first(where: { $0.id == id }) {
                let image = NSImage(contentsOf: session.url.appendingPathComponent("sheet.png"))
                SessionClipboard.copy(image: image, transcript: session.transcript)
            }
        case .setting, .model, .page:
            if let title = hit.highlightTitle {
                pulseHighlight(title)
            }
        }
    }

    private func extractNeedle(from hit: SettingsSearchHit) -> String? {
        guard let snippet = hit.snippet, let range = hit.matchRange,
              let swift = Range(range, in: snippet) else { return nil }
        return String(snippet[swift])
    }

    private func pulseHighlight(_ title: String) {
        highlightTitle = title
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_400_000_000)
            if highlightTitle == title {
                highlightTitle = nil
            }
        }
    }

    private func reloadUnlessRecent(_ window: CFTimeInterval) {
        if CACurrentMediaTime() - lastReloadAt.value < window { return }
        reload()
    }

    private func reload() {
        let started = CACurrentMediaTime()
        lastReloadAt.value = started
        sessions = SessionLibrary.load()
        if PerfHarness.isEnabled {
            PerfSuite.log(String(format: "reload sessions=%d ms=%.1f", sessions.count, (CACurrentMediaTime() - started) * 1000))
        }
    }
}

final class ReloadStamp {
    var value: CFTimeInterval = 0
}

@MainActor
final class SettingsPresenter {
    static let shared = SettingsPresenter()

    private var window: NSWindow?
    private let shownKey = "home.shown"

    /// Exposed for custom traffic lights (orderOut / miniaturize / zoom).
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

    /// Page requested before SettingsRoot exists. On a cold open the root
    /// is not subscribed yet when the notification below posts, so it reads
    /// this on appear instead (root cause of "Preferences… lands on Home").
    private var pendingPage: SettingsPage?

    func show(page: SettingsPage) {
        pendingPage = page
        show()
        NotificationCenter.default.post(name: .promptAnnotatorSettingsSelectPage, object: page.rawValue)
    }

    func takePendingPage() -> SettingsPage? {
        defer { pendingPage = nil }
        return pendingPage
    }

    private func ensure() -> NSWindow {
        if let window { return window }
        let root = SettingsRoot()
            .environmentObject(AppSettings.shared)
            .environmentObject(SessionController.shared)
            .focusEffectDisabled()
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
        // Wide enough for all eight folder tabs without truncation.
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
