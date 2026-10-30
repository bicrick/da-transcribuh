import Combine
import Foundation
import Sparkle

/// Sparkle 2 updater. One instance for the app.
///
/// Info.plist turns automatic checks on (`SUEnableAutomaticChecks` = YES). Silent installs stay
/// off (`SUAutomaticallyUpdate` = NO). docs/releasing.md covers the Sparkle feed.
@MainActor
final class UpdateController: ObservableObject {
    static let shared = UpdateController()

    /// Mirrors `SPUUpdater.canCheckForUpdates` (false while a check is already running).
    @Published private(set) var canCheckForUpdates = false

    private let controller: SPUStandardUpdaterController?

    private init() {
        // Unit tests host the app; never start an updater there.
        guard !Runtime.isUnitTest else {
            controller = nil
            return
        }
        let controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
        self.controller = controller
        controller.updater.publisher(for: \.canCheckForUpdates)
            .receive(on: RunLoop.main)
            .assign(to: &$canCheckForUpdates)
    }

    /// Starts the updater at launch. Safe to call more than once.
    func start() {
        _ = controller
    }

    /// User-initiated check. Sparkle shows its own progress and result windows.
    func checkForUpdates() {
        controller?.checkForUpdates(nil)
    }

    var automaticallyChecksForUpdates: Bool {
        controller?.updater.automaticallyChecksForUpdates ?? false
    }

    static let menuTitle = "Check for Updates…"

    /// Info.plist values, read without starting Sparkle (used by tests and the General page).
    enum Config {
        static var feedURL: String? { info("SUFeedURL") as? String }
        static var publicEDKey: String? { info("SUPublicEDKey") as? String }
        static var automaticChecksEnabled: Bool { (info("SUEnableAutomaticChecks") as? Bool) ?? false }
        static var requiresSignedFeed: Bool { (info("SURequireSignedFeed") as? Bool) ?? false }

        private static func info(_ key: String) -> Any? {
            Bundle.main.object(forInfoDictionaryKey: key)
        }
    }
}
