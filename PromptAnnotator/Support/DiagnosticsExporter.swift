import AppKit
import Foundation
import OSLog

/// Builds a local zip of logs, crash reports and a system summary. No network.
///
/// Contents: app.log (+ .1), errors.log (+ .1), this process's unified-log lines for our
/// subsystem, crash/hang reports for this app from ~/Library/Logs/DiagnosticReports,
/// and system.txt (versions, hardware, permissions, non-secret settings).
/// Never audio, transcripts or clipboard contents.
enum DiagnosticsExporter {
    static let crashNamePrefixes = ["da transcribuh", "PromptAnnotator"]
    static let crashExtensions: Set<String> = ["ips", "crash", "hang", "diag", "spin"]
    static let maxCrashReports = 25
    static let crashMaxAge: TimeInterval = 60 * 60 * 24 * 60

    /// Ask where to save, build off the main thread, then reveal the zip.
    @MainActor
    static func exportInteractively() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.zip]
        panel.canCreateDirectories = true
        panel.directoryURL = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first
        panel.nameFieldStringValue = defaultFileName(date: Date())
        guard panel.runModal() == .OK, let destination = panel.url else { return }
        let summary = systemSummary()
        AppLog.info("diagnostics export started")
        Task.detached(priority: .userInitiated) {
            do {
                try build(at: destination, systemSummary: summary)
                await MainActor.run {
                    NSWorkspace.shared.activateFileViewerSelecting([destination])
                }
            } catch {
                await MainActor.run {
                    let alert = NSAlert()
                    alert.messageText = "Couldn't export diagnostics"
                    alert.informativeText = error.localizedDescription
                    alert.runModal()
                }
            }
        }
    }

    static func defaultFileName(date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd-HHmm"
        return "da transcribuh diagnostics \(f.string(from: date)).zip"
    }

    struct Sources {
        var logFiles: [URL]
        var crashFolders: [URL]
        var unifiedLog: () -> String

        static var standard: Sources {
            let reports = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Logs/DiagnosticReports", isDirectory: true)
            let app = AppLog.fileURL
            let errors = URL(fileURLWithPath: errorLogPath)
            return Sources(
                logFiles: [app, URL(fileURLWithPath: app.path + ".1"),
                           errors, URL(fileURLWithPath: errors.path + ".1")],
                crashFolders: [reports, reports.appendingPathComponent("Retired", isDirectory: true)],
                unifiedLog: { DiagnosticsExporter.unifiedLogText() }
            )
        }
    }

    private static var errorLogPath: String {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return support.appendingPathComponent("PromptAnnotator/errors.log").path
    }

    /// Writes the zip at `destination` (replacing it). Synchronous; call off the main thread.
    static func build(at destination: URL, systemSummary: String, sources: Sources = .standard) throws {
        AppLog.flush()
        let fm = FileManager.default
        let staging = fm.temporaryDirectory
            .appendingPathComponent("dt-diagnostics-\(UUID().uuidString)", isDirectory: true)
        let root = staging.appendingPathComponent(
            destination.deletingPathExtension().lastPathComponent, isDirectory: true)
        try fm.createDirectory(at: root.appendingPathComponent("crash-reports"), withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: staging) }

        try systemSummary.write(to: root.appendingPathComponent("system.txt"), atomically: true, encoding: .utf8)
        for url in sources.logFiles where fm.fileExists(atPath: url.path) {
            try? fm.copyItem(at: url, to: root.appendingPathComponent(url.lastPathComponent))
        }
        try sources.unifiedLog().write(
            to: root.appendingPathComponent("unified-log.txt"), atomically: true, encoding: .utf8)
        for url in crashReports(in: sources.crashFolders, now: Date()) {
            try? fm.copyItem(at: url, to: root.appendingPathComponent("crash-reports/\(url.lastPathComponent)"))
        }

        try? fm.removeItem(at: destination)
        let ditto = Process()
        ditto.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        ditto.arguments = ["-c", "-k", "--sequesterRsrc", "--keepParent", root.path, destination.path]
        try ditto.run()
        ditto.waitUntilExit()
        guard ditto.terminationStatus == 0, fm.fileExists(atPath: destination.path) else {
            throw CocoaError(.fileWriteUnknown, userInfo: [
                NSLocalizedDescriptionKey: "Zipping failed (ditto exit \(ditto.terminationStatus)). The disk may be full."
            ])
        }
    }

    /// This app's reports, newest first, at most `maxCrashReports`, no older than `crashMaxAge`.
    static func crashReports(in folders: [URL], now: Date) -> [URL] {
        let fm = FileManager.default
        var found: [(URL, Date)] = []
        for folder in folders {
            guard let names = try? fm.contentsOfDirectory(atPath: folder.path) else { continue }
            for name in names {
                guard crashNamePrefixes.contains(where: { name.hasPrefix($0) }) else { continue }
                let url = folder.appendingPathComponent(name)
                guard crashExtensions.contains(url.pathExtension.lowercased()) else { continue }
                let modified = (try? fm.attributesOfItem(atPath: url.path)[.modificationDate] as? Date) ?? .distantPast
                guard now.timeIntervalSince(modified) <= crashMaxAge else { continue }
                found.append((url, modified))
            }
        }
        return found.sorted { $0.1 > $1.1 }.prefix(maxCrashReports).map(\.0)
    }

    /// Our subsystem's entries from this process (OSLogStore needs no entitlement for that scope).
    static func unifiedLogText() -> String {
        do {
            let store = try OSLogStore(scope: .currentProcessIdentifier)
            let start = store.position(timeIntervalSinceLatestBoot: 0)
            let predicate = NSPredicate(format: "subsystem == %@", AppLog.subsystem)
            let stamp = ISO8601DateFormatter.diagnostics
            var lines: [String] = []
            for case let entry as OSLogEntryLog in try store.getEntries(at: start, matching: predicate) {
                lines.append("\(stamp.string(from: entry.date)) [\(entry.category)] \(entry.composedMessage)")
                if lines.count >= 20_000 { lines.removeFirst(5_000) }
            }
            return lines.isEmpty ? "(no entries this launch)\n" : lines.joined(separator: "\n") + "\n"
        } catch {
            return "(unified log unavailable: \(error.localizedDescription))\n"
        }
    }

    /// Settings keys that look like secrets are dropped; long strings and blobs are summarized.
    static func redactedDefaults(_ domain: [String: Any]) -> [String] {
        let secretMarkers = ["key", "token", "secret", "password", "auth", "credential"]
        return domain.keys.sorted().compactMap { name in
            let lower = name.lowercased()
            if secretMarkers.contains(where: { lower.contains($0) }) && !lower.contains("hotkey") && !lower.contains("chord") {
                return "\(name) = <redacted>"
            }
            let value = domain[name]!
            switch value {
            case let data as Data: return "\(name) = <\(data.count) bytes>"
            case let string as String where string.count > 120: return "\(name) = <\(string.count) chars>"
            case let array as [Any] where array.count > 20: return "\(name) = <\(array.count) items>"
            default: return "\(name) = \(value)"
            }
        }
    }

    @MainActor
    static func systemSummary() -> String {
        let info = ProcessInfo.processInfo
        let perms = Permissions.current()
        var lines = [
            "da transcribuh \(AppVersion.label)",
            "bundle \(Bundle.main.bundlePath)",
            "macOS \(info.operatingSystemVersionString)",
            "model \(sysctlString("hw.model") ?? "?") cpu \(sysctlString("machdep.cpu.brand_string") ?? "?")",
            "memory \(info.physicalMemory / 1_073_741_824) GB, cores \(info.activeProcessorCount)",
            "thermal \(info.thermalState.rawValue), low power \(info.isLowPowerModeEnabled)",
            "uptime \(Int(info.systemUptime)) s, app uptime \(Int(Date().timeIntervalSince(launchDate))) s",
            "permissions accessibility=\(perms.accessibility) microphone=\(perms.microphone) screen=\(perms.screen)",
            "exported \(ISO8601DateFormatter.diagnostics.string(from: Date()))",
            "",
            "[settings]",
        ]
        if let id = Bundle.main.bundleIdentifier, let domain = UserDefaults.standard.persistentDomain(forName: id) {
            lines += redactedDefaults(domain)
        }
        return lines.joined(separator: "\n") + "\n"
    }

    static let launchDate = Date()

    private static func sysctlString(_ name: String) -> String? {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname(name, &buffer, &size, nil, 0) == 0 else { return nil }
        return String(cString: buffer)
    }
}
