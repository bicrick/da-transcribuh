import AppKit
import Foundation
import os
import QuartzCore

/// Cheap always-on timing for Settings tab switches and the clipboard panel.
/// Intervals show in Instruments (os_signpost, subsystem com.bicrick.PromptAnnotator, category perf).
/// A switch ends on the first main-queue turn after the new page's onAppear,
/// which is after SwiftUI has built, laid out and committed it.
@MainActor
enum PerfProbe {
    static let signposter = OSSignposter(subsystem: "com.bicrick.PromptAnnotator", category: "perf")
    private static let logger = Logger(subsystem: "com.bicrick.PromptAnnotator", category: "perf")

    private struct Pending {
        var label: String
        var start: CFTimeInterval
        var state: OSSignpostIntervalState
    }

    private static var pending: [String: Pending] = [:]

    /// Starts an interval under `key` (for example "tab" or "panel").
    static func begin(_ key: String, _ label: String) {
        let state = signposter.beginInterval("switch", id: signposter.makeSignpostID(), "\(key, privacy: .public) \(label, privacy: .public)")
        pending[key] = Pending(label: label, start: CACurrentMediaTime(), state: state)
    }

    /// Ends the interval for `key` after the current update commits.
    static func endAfterCommit(_ key: String) {
        DispatchQueue.main.async {
            MainActor.assumeIsolated { end(key) }
        }
    }

    /// Ends the interval for `key` after Core Animation commits this run-loop
    /// turn (an observer ordered after CA's own commit observer). Used for
    /// AppKit-driven opens like the clipboard panel, where there is no
    /// SwiftUI onAppear to hang off.
    static func endAfterDisplay(_ key: String) {
        let observer = CFRunLoopObserverCreateWithHandler(
            kCFAllocatorDefault,
            CFRunLoopActivity.beforeWaiting.rawValue,
            false,
            3_000_000
        ) { _, _ in
            MainActor.assumeIsolated { end(key) }
        }
        CFRunLoopAddObserver(CFRunLoopGetMain(), observer, .commonModes)
    }

    private static func end(_ key: String) {
        guard let item = pending.removeValue(forKey: key) else { return }
        signposter.endInterval("switch", item.state)
        let ms = (CACurrentMediaTime() - item.start) * 1000
        let line = String(format: "dtperf %@ %@ %.1f", key, item.label, ms)
        logger.log("\(line, privacy: .public)")
        if PerfHarness.isEnabled {
            FileHandle.standardError.write(Data((line + "\n").utf8))
        }
    }
}

/// Launch with `-DTPerfTabCycle <rounds>` to walk every Settings tab in order and log each switch.
/// `-DTPerfTabs history,home` limits the walk. `-DTPerfDelayMs <ms>` waits before the walk (default 2000). `-DTPerfQuit YES` quits when it ends. No effect without the argument.
@MainActor
enum PerfHarness {
    static var rounds: Int {
        UserDefaults.standard.integer(forKey: "DTPerfTabCycle")
    }

    static var isEnabled: Bool { rounds > 0 || UserDefaults.standard.integer(forKey: "DTPerfPanel") > 0 }

    private static var started = false

    static func runTabCycle(select: @escaping @MainActor (SettingsPage) -> Void) {
        guard rounds > 0, !started else { return }
        started = true
        let custom = (UserDefaults.standard.string(forKey: "DTPerfTabs") ?? "")
            .split(separator: ",")
            .compactMap { SettingsPage(rawValue: String($0)) }
        let order = custom.isEmpty ? SettingsPage.tabOrder : custom
        Task { @MainActor in
            let delayMs = UserDefaults.standard.integer(forKey: "DTPerfDelayMs")
            try? await Task.sleep(nanoseconds: UInt64(delayMs > 0 ? delayMs : 2000) * 1_000_000)
            for _ in 0..<rounds {
                for page in order {
                    select(page)
                    try? await Task.sleep(nanoseconds: 600_000_000)
                }
            }
            FileHandle.standardError.write(Data("dtperf done\n".utf8))
            if UserDefaults.standard.bool(forKey: "DTPerfQuit") {
                NSApp.terminate(nil)
            }
        }
    }
}

extension PerfHarness {
    /// Launch with `-DTPerfPanel <count>` to open and close the clipboard
    /// panel `count` times (logs `dtperf panel open <ms>`). Honors
    /// `-DTPerfDelayMs` and `-DTPerfQuit`.
    static func runPanelCycle() {
        let count = UserDefaults.standard.integer(forKey: "DTPerfPanel")
        guard count > 0 else { return }
        let delayMs = UserDefaults.standard.integer(forKey: "DTPerfDelayMs")
        after(ms: delayMs > 0 ? delayMs : 2000) { panelStep(remaining: count) }
    }

    private static func panelStep(remaining: Int) {
        guard remaining > 0 else {
            FileHandle.standardError.write(Data("dtperf done\n".utf8))
            if UserDefaults.standard.bool(forKey: "DTPerfQuit") {
                NSApp.terminate(nil)
            }
            return
        }
        ClipboardHistoryPanelController.shared.show()
        after(ms: 700) {
            ClipboardHistoryPanelController.shared.hide()
            after(ms: 300) { panelStep(remaining: remaining - 1) }
        }
    }

    private static func after(ms: Int, _ work: @escaping @MainActor () -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(ms)) {
            MainActor.assumeIsolated { work() }
        }
    }
}
