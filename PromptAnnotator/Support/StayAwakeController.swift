import Foundation
import IOKit
import IOKit.ps
import IOKit.pwr_mgt

// MARK: - Types

enum StayAwakeMode: String, CaseIterable, Identifiable, Codable, Sendable {
    case off
    case lidOpen
    case lidClosed

    var id: String { rawValue }

    /// Active modes selectable as defaults or quick switches.
    static var activeModes: [StayAwakeMode] { [.lidClosed, .lidOpen] }

    var isActive: Bool { self != .off }

    var title: String {
        switch self {
        case .off: return "Off"
        case .lidOpen: return "Lid open only"
        case .lidClosed: return "Lid closed (no monitor)"
        }
    }

    var shortLabel: String {
        switch self {
        case .off: return "off"
        case .lidOpen: return "lid open"
        case .lidClosed: return "lid closed"
        }
    }

    var detail: String {
        switch self {
        case .off: return "Normal macOS sleep."
        case .lidOpen: return "Prevents idle and display sleep while open. No admin password."
        case .lidClosed: return "Keeps the Mac running with the lid closed via pmset disablesleep."
        }
    }

    static func storedDefault(_ raw: String?) -> StayAwakeMode {
        guard let raw, let parsed = StayAwakeMode(rawValue: raw), parsed != .off else {
            return .lidClosed
        }
        return parsed
    }
}

enum StayAwakeDuration: String, CaseIterable, Identifiable, Codable, Sendable {
    case indefinite
    case oneHour
    case twoHours
    case fourHours

    var id: String { rawValue }

    var shortLabel: String {
        switch self {
        case .indefinite: return "inf"
        case .oneHour: return "1h"
        case .twoHours: return "2h"
        case .fourHours: return "4h"
        }
    }

    var title: String {
        switch self {
        case .indefinite: return "Indefinitely"
        case .oneHour: return "1 hour"
        case .twoHours: return "2 hours"
        case .fourHours: return "4 hours"
        }
    }

    var seconds: TimeInterval? {
        switch self {
        case .indefinite: return nil
        case .oneHour: return 3600
        case .twoHours: return 7200
        case .fourHours: return 14_400
        }
    }

    static func stored(_ raw: String?) -> StayAwakeDuration {
        StayAwakeDuration(rawValue: raw ?? "") ?? .indefinite
    }
}

enum StayAwakeBatteryCutoff {
    static let presets: [Int] = [0, 10, 20, 30]
    static let defaultPercent: Int = 20
    /// Hard emergency floor even when manually started below the user's cutoff.
    static let criticalFloorPercent: Int = 5

    static func sanitize(_ raw: Int) -> Int {
        presets.contains(raw) ? raw : defaultPercent
    }

    static func title(for percent: Int) -> String {
        percent <= 0 ? "Off" : "\(percent)%"
    }
}

enum StayAwakeIndicatorState: Equatable, Sendable {
    case inactive
    case lidOpen
    case lidClosed
}

struct StayAwakePowerSnapshot: Equatable, Sendable {
    var hasBattery: Bool
    var onBattery: Bool
    var batteryPercent: Int?

    static let desktopAC = StayAwakePowerSnapshot(hasBattery: false, onBattery: false, batteryPercent: nil)
}

enum StayAwakePrivilegedResult: Equatable, Sendable {
    case succeeded
    case cancelled
    case failed(String)
}

// MARK: - Sudoers & pmset Helpers (pure / unit-testable)

enum StayAwakeSudoersRule {
    static let path = "/etc/sudoers.d/da-transcribuh-sleep"
    static let pmsetPath = "/usr/bin/pmset"
    static let removeAndRestoreCommand =
        "/usr/bin/pmset -a disablesleep 0 && /bin/rm -f /etc/sudoers.d/da-transcribuh-sleep"

    /// Strict POSIX username validation so shell commands can never be injected.
    static func isValidUsername(_ username: String) -> Bool {
        guard !username.isEmpty, username.count <= 64 else { return false }
        return username.unicodeScalars.allSatisfy { scalar in
            (scalar >= "a" && scalar <= "z")
                || (scalar >= "A" && scalar <= "Z")
                || (scalar >= "0" && scalar <= "9")
                || scalar == "_" || scalar == "-" || scalar == "."
        }
    }

    static func ruleLines(for username: String) -> [String]? {
        guard isValidUsername(username) else { return nil }
        return [
            "# Managed by da transcribuh (closed-lid stay awake)",
            "\(username) ALL=(root) NOPASSWD: /usr/bin/pmset -a disablesleep 0, /usr/bin/pmset -a disablesleep 1",
        ]
    }

    static func ruleContent(for username: String) -> String? {
        guard let lines = ruleLines(for: username) else { return nil }
        return lines.joined(separator: "\n") + "\n"
    }

    /// Shell script that atomically validates (`visudo -cf`) and installs the scoped sudoers rule,
    /// optionally also flipping `pmset -a disablesleep <0|1>` in the same single admin prompt.
    static func installCommand(username: String, setSleepDisabled: Bool? = nil) -> String? {
        guard let lines = ruleLines(for: username) else { return nil }
        let line1 = lines[0]
        let line2 = lines[1]
        var steps = [
            "set -e",
            "TMP=$(/usr/bin/mktemp /tmp/da-transcribuh-sudoers.XXXXXX)",
            "trap '/bin/rm -f \"$TMP\"' EXIT",
            "printf '%s\\n' '\(line1)' '\(line2)' > \"$TMP\"",
            "/bin/chmod 0440 \"$TMP\"",
            "/usr/sbin/chown root:wheel \"$TMP\"",
            "/usr/sbin/visudo -cf \"$TMP\"",
            "/bin/mv -f \"$TMP\" '\(path)'",
        ]
        if let setSleepDisabled {
            steps.append("/usr/bin/pmset -a disablesleep \(setSleepDisabled ? 1 : 0)")
        }
        return steps.joined(separator: "; ")
    }

    /// Builds an AppleScript source invoking `do shell script ... with prompt ... with administrator privileges`.
    static func appleScriptCommand(shellScript: String, prompt: String) -> String {
        let escapedScript = escapeForAppleScriptString(shellScript)
        let escapedPrompt = escapeForAppleScriptString(prompt)
        return "do shell script \"\(escapedScript)\" with prompt \"\(escapedPrompt)\" with administrator privileges"
    }

    static func escapeForAppleScriptString(_ raw: String) -> String {
        raw
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }

    /// Parses `pmset -g` output for `SleepDisabled 1`.
    static func parsePmsetSleepDisabled(_ output: String) -> Bool {
        for rawLine in output.split(whereSeparator: \.isNewline) {
            let trimmed = rawLine.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("SleepDisabled") else { continue }
            let parts = trimmed.split(whereSeparator: \.isWhitespace)
            if parts.count >= 2, parts[0] == "SleepDisabled" {
                return parts[1] == "1"
            }
        }
        return false
    }

    /// Formats remaining countdown time for compact menu-bar metadata.
    static func formatRemaining(_ seconds: TimeInterval) -> String {
        let clamped = max(0, Int(ceil(seconds)))
        if clamped < 60 { return "<1m left" }
        let totalMinutes = (clamped + 59) / 60
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        if hours > 0, minutes > 0 {
            return "\(hours)h \(minutes)m left"
        }
        if hours > 0 {
            return "\(hours)h left"
        }
        return "\(minutes)m left"
    }
}

// MARK: - System Bridge

protocol StayAwakeSystemBridge: AnyObject, Sendable {
    func readSleepDisabled() -> Bool
    func hasPasswordlessHelper() -> Bool
    func setSleepDisabled(_ disabled: Bool, allowAdminPrompt: Bool) -> StayAwakePrivilegedResult
    func installPasswordlessHelper() -> StayAwakePrivilegedResult
    func removePasswordlessHelper() -> StayAwakePrivilegedResult
    func acquireIdleAssertion(preventDisplaySleep: Bool) -> Bool
    func releaseIdleAssertion()
    func readPowerSnapshot() -> StayAwakePowerSnapshot
    func startPowerSourceObserver(_ handler: @escaping @Sendable () -> Void)
    func stopPowerSourceObserver()
}

final class LiveStayAwakeSystemBridge: StayAwakeSystemBridge, @unchecked Sendable {
    private let lock = NSLock()
    private var assertionID: IOPMAssertionID = 0
    private var hasAssertion = false
    private var powerSourceRunLoopSource: CFRunLoopSource?
    private var powerCallbackContext: UnsafeMutableRawPointer?

    func readSleepDisabled() -> Bool {
        // Fast in-process kernel read (no subprocess needed).
        let service = IOServiceGetMatchingService(
            kIOMainPortDefault,
            IOServiceMatching("IOPMrootDomain")
        )
        if service != 0 {
            defer { IOObjectRelease(service) }
            if let prop = IORegistryEntryCreateCFProperty(
                service,
                "SleepDisabled" as CFString,
                kCFAllocatorDefault,
                0
            )?.takeRetainedValue() {
                if let boolValue = prop as? Bool {
                    return boolValue
                }
                if let number = prop as? NSNumber {
                    return number.boolValue
                }
            }
        }
        // Fallback to `pmset -g` if property wasn't present on IOPMrootDomain.
        let result = runProcess("/usr/bin/pmset", arguments: ["-g"])
        guard result.status == 0 else { return false }
        return StayAwakeSudoersRule.parsePmsetSleepDisabled(result.stdout)
    }

    func hasPasswordlessHelper() -> Bool {
        FileManager.default.fileExists(atPath: StayAwakeSudoersRule.path)
    }

    func setSleepDisabled(_ disabled: Bool, allowAdminPrompt: Bool) -> StayAwakePrivilegedResult {
        let value = disabled ? "1" : "0"
        // Fast path: passwordless sudo via our scoped sudoers rule (<30 ms, no prompt).
        let fast = runProcess("/usr/bin/sudo", arguments: ["-n", StayAwakeSudoersRule.pmsetPath, "-a", "disablesleep", value])
        if fast.status == 0 {
            return .succeeded
        }
        guard allowAdminPrompt else {
            return .failed(fast.stderr.isEmpty ? "Passwordless helper is not installed." : fast.stderr)
        }
        // Admin prompt path.
        if disabled {
            let username = NSUserName()
            guard let shell = StayAwakeSudoersRule.installCommand(username: username, setSleepDisabled: true) else {
                return .failed("Could not prepare closed-lid rule for user \(username).")
            }
            return runAdminShell(
                shell,
                prompt: "da transcribuh needs administrator access once so toggling closed-lid stay awake works without prompts."
            )
        } else {
            return runAdminShell(
                "\(StayAwakeSudoersRule.pmsetPath) -a disablesleep 0",
                prompt: "da transcribuh needs administrator access to restore normal Mac sleep."
            )
        }
    }

    func installPasswordlessHelper() -> StayAwakePrivilegedResult {
        let username = NSUserName()
        guard let shell = StayAwakeSudoersRule.installCommand(username: username, setSleepDisabled: nil) else {
            return .failed("Could not prepare closed-lid rule for user \(username).")
        }
        return runAdminShell(
            shell,
            prompt: "da transcribuh needs administrator access once to install its passwordless closed-lid sleep rule."
        )
    }

    func removePasswordlessHelper() -> StayAwakePrivilegedResult {
        runAdminShell(
            StayAwakeSudoersRule.removeAndRestoreCommand,
            prompt: "da transcribuh needs administrator access to remove its closed-lid sleep rule and restore normal sleep."
        )
    }

    func acquireIdleAssertion(preventDisplaySleep: Bool) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        releaseAssertionLocked()
        let assertionType: CFString = preventDisplaySleep
            ? (kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString)
            : (kIOPMAssertionTypePreventUserIdleSystemSleep as CFString)
        let reason = (preventDisplaySleep
            ? "da transcribuh stay awake (lid open)"
            : "da transcribuh stay awake (lid closed)") as CFString
        var newID: IOPMAssertionID = 0
        let status = IOPMAssertionCreateWithName(
            assertionType,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            reason,
            &newID
        )
        if status == kIOReturnSuccess {
            assertionID = newID
            hasAssertion = true
            return true
        }
        return false
    }

    func releaseIdleAssertion() {
        lock.lock()
        defer { lock.unlock() }
        releaseAssertionLocked()
    }

    private func releaseAssertionLocked() {
        guard hasAssertion else { return }
        IOPMAssertionRelease(assertionID)
        assertionID = 0
        hasAssertion = false
    }

    func readPowerSnapshot() -> StayAwakePowerSnapshot {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef],
              !list.isEmpty else {
            return .desktopAC
        }
        var foundBattery = false
        var onBattery = false
        var percent: Int?
        for source in list {
            guard let desc = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any] else {
                continue
            }
            let type = desc[kIOPSTypeKey as String] as? String
            guard type == (kIOPSInternalBatteryType as String) else { continue }
            foundBattery = true
            let state = desc[kIOPSPowerSourceStateKey as String] as? String
            onBattery = (state == (kIOPSBatteryPowerValue as String))
            if let current = desc[kIOPSCurrentCapacityKey as String] as? Int,
               let maxCap = desc[kIOPSMaxCapacityKey as String] as? Int,
               maxCap > 0 {
                percent = min(100, max(0, Int((Double(current) / Double(maxCap) * 100.0).rounded())))
            }
            break
        }
        return StayAwakePowerSnapshot(
            hasBattery: foundBattery,
            onBattery: onBattery,
            batteryPercent: percent
        )
    }

    private final class PowerCallbackBox {
        let handler: @Sendable () -> Void
        init(_ handler: @escaping @Sendable () -> Void) { self.handler = handler }
    }

    func startPowerSourceObserver(_ handler: @escaping @Sendable () -> Void) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.stopPowerSourceObserverOnMain()
            let box = PowerCallbackBox(handler)
            let context = Unmanaged.passRetained(box).toOpaque()
            let callback: IOPowerSourceCallbackType = { rawContext in
                guard let rawContext else { return }
                let box = Unmanaged<PowerCallbackBox>.fromOpaque(rawContext).takeUnretainedValue()
                box.handler()
            }
            if let source = IOPSNotificationCreateRunLoopSource(callback, context)?.takeRetainedValue() {
                CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode)
                self.lock.lock()
                self.powerSourceRunLoopSource = source
                self.powerCallbackContext = context
                self.lock.unlock()
            } else {
                Unmanaged<PowerCallbackBox>.fromOpaque(context).release()
            }
        }
    }

    func stopPowerSourceObserver() {
        if Thread.isMainThread {
            stopPowerSourceObserverOnMain()
        } else {
            DispatchQueue.main.async { [weak self] in
                self?.stopPowerSourceObserverOnMain()
            }
        }
    }

    private func stopPowerSourceObserverOnMain() {
        lock.lock()
        let source = powerSourceRunLoopSource
        let context = powerCallbackContext
        powerSourceRunLoopSource = nil
        powerCallbackContext = nil
        lock.unlock()

        if let source {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .defaultMode)
        }
        if let context {
            Unmanaged<PowerCallbackBox>.fromOpaque(context).release()
        }
    }

    // MARK: - Subprocess helpers

    private func runAdminShell(_ shellScript: String, prompt: String) -> StayAwakePrivilegedResult {
        let appleScript = StayAwakeSudoersRule.appleScriptCommand(shellScript: shellScript, prompt: prompt)
        let result = runProcess("/usr/bin/osascript", arguments: ["-e", appleScript])
        if result.status == 0 {
            return .succeeded
        }
        let err = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
        if err.contains("-128") || err.localizedCaseInsensitiveContains("User canceled") {
            return .cancelled
        }
        return .failed(err.isEmpty ? "Administrator command failed (exit \(result.status))." : err)
    }

    private func runProcess(_ executable: String, arguments: [String]) -> (status: Int32, stdout: String, stderr: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe
        do {
            try process.run()
        } catch {
            return (-1, "", error.localizedDescription)
        }
        let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
        let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (
            process.terminationStatus,
            String(data: outData, encoding: .utf8) ?? "",
            String(data: errData, encoding: .utf8) ?? ""
        )
    }
}

// MARK: - Controller

@MainActor
final class StayAwakeController: ObservableObject {
    static let shared = StayAwakeController()

    @Published private(set) var mode: StayAwakeMode = .off
    @Published private(set) var duration: StayAwakeDuration
    @Published private(set) var expiresAt: Date?
    @Published private(set) var remainingText: String?
    @Published private(set) var isBusy: Bool = false
    /// True when system `SleepDisabled` is 1, but `da transcribuh` did not start the session.
    @Published private(set) var externallyDisabled: Bool = false
    @Published private(set) var helperInstalled: Bool = false
    @Published private(set) var statusMessage: String?
    @Published private(set) var statusIsError: Bool = false
    @Published private(set) var powerSnapshot: StayAwakePowerSnapshot = .desktopAC

    private let bridge: StayAwakeSystemBridge
    private let settings: AppSettings
    private let now: () -> Date
    private var tickTimer: Timer?
    private var startedBelowCutoff = false

    init(
        bridge: StayAwakeSystemBridge = LiveStayAwakeSystemBridge(),
        settings: AppSettings? = nil,
        now: @escaping () -> Date = Date.init
    ) {
        let resolvedSettings = settings ?? .shared
        self.bridge = bridge
        self.settings = resolvedSettings
        self.now = now
        self.duration = resolvedSettings.stayAwakeDefaultDuration
        self.helperInstalled = bridge.hasPasswordlessHelper()
    }

    var isActive: Bool {
        mode.isActive || externallyDisabled
    }

    var indicatorState: StayAwakeIndicatorState {
        if mode == .lidClosed || externallyDisabled {
            return .lidClosed
        }
        if mode == .lidOpen {
            return .lidOpen
        }
        return .inactive
    }

    var menuToggleTitle: String {
        if isBusy { return "stay awake: working…" }
        if externallyDisabled && mode == .off { return "stay awake: lid closed" }
        return "stay awake: \(mode.shortLabel)"
    }

    var menuStatusLine: String {
        if externallyDisabled && mode == .off {
            return "Sleep disabled externally · click to restore"
        }
        switch mode {
        case .off:
            let preferred = settings.stayAwakeDefaultMode
            if preferred == .lidClosed {
                return "Keeps Mac running with lid closed"
            }
            return "Keeps Mac awake while lid is open"
        case .lidOpen, .lidClosed:
            var parts: [String] = []
            if let remainingText {
                parts.append(remainingText)
            } else {
                parts.append("Indefinite")
            }
            if powerSnapshot.hasBattery {
                if powerSnapshot.onBattery, let pct = powerSnapshot.batteryPercent {
                    let cutoff = settings.stayAwakeBatteryCutoff
                    if cutoff > 0 && !startedBelowCutoff {
                        parts.append("\(pct)% · cutoff \(cutoff)%")
                    } else {
                        parts.append("\(pct)% batt")
                    }
                } else {
                    parts.append("plugged in")
                }
            }
            return parts.joined(separator: " · ")
        }
    }

    /// Refreshes real system `SleepDisabled`, helper install state, and battery state.
    func refreshSystemState() {
        let systemDisabled = bridge.readSleepDisabled()
        helperInstalled = bridge.hasPasswordlessHelper()
        powerSnapshot = bridge.readPowerSnapshot()

        if mode == .lidClosed {
            if !systemDisabled {
                // Something external (e.g., Terminal `pmset -a disablesleep 0`) turned sleep back on.
                bridge.releaseIdleAssertion()
                mode = .off
                expiresAt = nil
                remainingText = nil
                stopMonitoring()
                externallyDisabled = false
                AppLog.info("stayAwake: SleepDisabled cleared externally; synced to off")
            } else {
                externallyDisabled = false
                evaluateSafetyAndTimer()
            }
        } else {
            externallyDisabled = systemDisabled
            if mode == .lidOpen {
                evaluateSafetyAndTimer()
            }
        }
    }

    /// One-click menu bar toggle: turns OFF if active (or externally disabled),
    /// otherwise turns ON using the user's default mode (defaults to `.lidClosed`).
    func togglePrimary() {
        guard !isBusy else { return }
        if isActive {
            Task { await setMode(.off) }
        } else {
            let target = settings.stayAwakeDefaultMode
            duration = settings.stayAwakeDefaultDuration
            Task { await setMode(target) }
        }
    }

    func selectMode(_ target: StayAwakeMode) {
        guard !isBusy else { return }
        if target == mode && !(target == .off && externallyDisabled) { return }
        Task { await setMode(target) }
    }

    func setDuration(_ newDuration: StayAwakeDuration) {
        duration = newDuration
        settings.setStayAwakeDefaultDuration(newDuration)
        guard mode.isActive else { return }
        applyDeadline(for: newDuration)
    }

    func installHelper() {
        guard !isBusy else { return }
        isBusy = true
        statusMessage = nil
        statusIsError = false
        let bridge = self.bridge
        Task {
            let result = await Self.runOffMain { bridge.installPasswordlessHelper() }
            self.isBusy = false
            self.helperInstalled = bridge.hasPasswordlessHelper()
            switch result {
            case .succeeded:
                self.statusMessage = "Closed-lid helper installed."
                self.statusIsError = false
                AppLog.info("stayAwake: passwordless sudoers helper installed")
            case .cancelled:
                break
            case .failed(let message):
                self.statusMessage = message
                self.statusIsError = true
                AppLog.error("stayAwake: install helper failed: \(message)")
            }
        }
    }

    func removeHelper() {
        guard !isBusy else { return }
        isBusy = true
        statusMessage = nil
        statusIsError = false
        let bridge = self.bridge
        Task {
            let result = await Self.runOffMain { bridge.removePasswordlessHelper() }
            self.isBusy = false
            self.helperInstalled = bridge.hasPasswordlessHelper()
            switch result {
            case .succeeded:
                if self.mode == .lidClosed {
                    bridge.releaseIdleAssertion()
                    self.mode = .off
                    self.expiresAt = nil
                    self.remainingText = nil
                    self.stopMonitoring()
                }
                self.externallyDisabled = bridge.readSleepDisabled()
                self.statusMessage = "Closed-lid helper removed."
                self.statusIsError = false
                AppLog.info("stayAwake: passwordless sudoers helper removed")
            case .cancelled:
                break
            case .failed(let message):
                self.statusMessage = message
                self.statusIsError = true
                AppLog.error("stayAwake: remove helper failed: \(message)")
            }
        }
    }

    func setMode(_ target: StayAwakeMode, reason: String? = nil, allowAdminPrompt: Bool = true) async {
        guard !isBusy else { return }
        let previousMode = mode
        let needsDisablePmset = (previousMode == .lidClosed || externallyDisabled) && target != .lidClosed
        let needsEnablePmset = (target == .lidClosed) && (previousMode != .lidClosed)

        statusMessage = nil
        statusIsError = false

        if needsEnablePmset {
            isBusy = true
            let bridge = self.bridge
            let result = await Self.runOffMain {
                bridge.setSleepDisabled(true, allowAdminPrompt: allowAdminPrompt)
            }
            isBusy = false
            helperInstalled = bridge.hasPasswordlessHelper()
            switch result {
            case .succeeded:
                break
            case .cancelled:
                return
            case .failed(let message):
                statusMessage = message
                statusIsError = true
                AppLog.error("stayAwake: enable disablesleep failed: \(message)")
                return
            }
        } else if needsDisablePmset {
            isBusy = true
            let bridge = self.bridge
            let result = await Self.runOffMain {
                bridge.setSleepDisabled(false, allowAdminPrompt: allowAdminPrompt)
            }
            isBusy = false
            helperInstalled = bridge.hasPasswordlessHelper()
            switch result {
            case .succeeded:
                externallyDisabled = false
            case .cancelled:
                return
            case .failed(let message):
                // Re-read real state in case SleepDisabled is already 0.
                let stillDisabled = bridge.readSleepDisabled()
                if stillDisabled {
                    statusMessage = message
                    statusIsError = true
                    AppLog.error("stayAwake: disable disablesleep failed: \(message)")
                    return
                }
                externallyDisabled = false
            }
        }

        switch target {
        case .off:
            bridge.releaseIdleAssertion()
            mode = .off
            expiresAt = nil
            remainingText = nil
            startedBelowCutoff = false
            stopMonitoring()
            if let reason {
                statusMessage = reason
                statusIsError = false
            }
            AppLog.info("stayAwake: off\(reason.map { " (\($0))" } ?? "")")

        case .lidOpen:
            _ = bridge.acquireIdleAssertion(preventDisplaySleep: true)
            mode = .lidOpen
            externallyDisabled = false
            configureActiveSession(preserveDeadline: previousMode.isActive)
            AppLog.info("stayAwake: lidOpen duration=\(duration.rawValue)")

        case .lidClosed:
            _ = bridge.acquireIdleAssertion(preventDisplaySleep: false)
            mode = .lidClosed
            externallyDisabled = false
            configureActiveSession(preserveDeadline: previousMode.isActive)
            AppLog.info("stayAwake: lidClosed duration=\(duration.rawValue)")
        }
    }

    /// Synchronous, non-prompting cleanup for `NSApplicationDelegate.applicationWillTerminate`.
    func shutdown() {
        stopMonitoring()
        bridge.releaseIdleAssertion()
        if mode == .lidClosed, settings.stayAwakeRestoreOnQuit {
            let result = bridge.setSleepDisabled(false, allowAdminPrompt: false)
            switch result {
            case .succeeded:
                AppLog.info("stayAwake: restored normal sleep on quit")
            case .cancelled:
                break
            case .failed(let message):
                AppLog.error("stayAwake: could not restore sleep on quit: \(message)")
            }
        }
        mode = .off
        expiresAt = nil
        remainingText = nil
    }

    /// Exposed for unit tests to drive timer/battery checks deterministically.
    func evaluateSafetyAndTimer() {
        guard mode.isActive else { return }
        powerSnapshot = bridge.readPowerSnapshot()

        // 1. Check expiration timer.
        if let deadline = expiresAt {
            let remaining = deadline.timeIntervalSince(now())
            if remaining <= 0 {
                Task { await setMode(.off, reason: "Timer ended", allowAdminPrompt: false) }
                return
            }
            remainingText = StayAwakeSudoersRule.formatRemaining(remaining)
        } else {
            remainingText = nil
        }

        // 2. Check battery safety cutoff.
        guard powerSnapshot.hasBattery, powerSnapshot.onBattery,
              let pct = powerSnapshot.batteryPercent else {
            // Plugged back in — re-arm normal cutoff if it was previously bypassed.
            if startedBelowCutoff, !powerSnapshot.onBattery {
                startedBelowCutoff = false
                if statusMessage?.hasPrefix("Low battery") == true {
                    statusMessage = nil
                }
            }
            return
        }

        let cutoff = settings.stayAwakeBatteryCutoff
        if startedBelowCutoff {
            // User deliberately enabled while already below cutoff: only enforce emergency floor.
            if pct <= StayAwakeBatteryCutoff.criticalFloorPercent {
                Task {
                    await setMode(.off, reason: "Stopped at \(pct)% battery", allowAdminPrompt: false)
                }
            }
            return
        }

        if cutoff > 0, pct <= cutoff {
            Task {
                await setMode(.off, reason: "Stopped at \(pct)% battery", allowAdminPrompt: false)
            }
        }
    }

    // MARK: - Private helpers

    private func configureActiveSession(preserveDeadline: Bool) {
        powerSnapshot = bridge.readPowerSnapshot()
        let cutoff = settings.stayAwakeBatteryCutoff
        if powerSnapshot.hasBattery,
           powerSnapshot.onBattery,
           let pct = powerSnapshot.batteryPercent,
           cutoff > 0,
           pct <= cutoff {
            startedBelowCutoff = true
            statusMessage = "Low battery (\(pct)%) — plug in soon"
            statusIsError = false
        } else {
            startedBelowCutoff = false
        }

        if !preserveDeadline || expiresAt == nil {
            applyDeadline(for: duration)
        } else {
            updateRemainingText()
        }
        startMonitoring()
    }

    private func applyDeadline(for duration: StayAwakeDuration) {
        if let seconds = duration.seconds {
            expiresAt = now().addingTimeInterval(seconds)
        } else {
            expiresAt = nil
        }
        updateRemainingText()
    }

    private func updateRemainingText() {
        guard let deadline = expiresAt else {
            remainingText = nil
            return
        }
        remainingText = StayAwakeSudoersRule.formatRemaining(deadline.timeIntervalSince(now()))
    }

    private func startMonitoring() {
        stopMonitoring()
        bridge.startPowerSourceObserver { [weak self] in
            Task { @MainActor [weak self] in
                self?.evaluateSafetyAndTimer()
            }
        }
        let timer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.evaluateSafetyAndTimer()
            }
        }
        timer.tolerance = 3
        tickTimer = timer
    }

    private func stopMonitoring() {
        tickTimer?.invalidate()
        tickTimer = nil
        bridge.stopPowerSourceObserver()
    }

    private static func runOffMain<T: Sendable>(_ work: @escaping @Sendable () -> T) async -> T {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(returning: work())
            }
        }
    }
}
