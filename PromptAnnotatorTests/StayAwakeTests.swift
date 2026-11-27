import AppKit
import SwiftUI
import XCTest
@testable import PromptAnnotator

// MARK: - Deterministic Fake Bridge

private final class FakeStayAwakeBridge: StayAwakeSystemBridge, @unchecked Sendable {
    var sleepDisabled = false
    var passwordlessHelper = false
    var nextSetResult: StayAwakePrivilegedResult = .succeeded
    var nextInstallResult: StayAwakePrivilegedResult = .succeeded
    var nextRemoveResult: StayAwakePrivilegedResult = .succeeded
    var powerSnapshot = StayAwakePowerSnapshot(hasBattery: true, onBattery: false, batteryPercent: 85)

    var setCalls: [(disabled: Bool, allowAdminPrompt: Bool)] = []
    var assertionCalls: [Bool] = []
    var releaseCalls = 0
    var observerStartCalls = 0
    var observerStopCalls = 0
    var activePowerHandler: (@Sendable () -> Void)?

    func readSleepDisabled() -> Bool { sleepDisabled }
    func hasPasswordlessHelper() -> Bool { passwordlessHelper }

    func setSleepDisabled(_ disabled: Bool, allowAdminPrompt: Bool) -> StayAwakePrivilegedResult {
        setCalls.append((disabled, allowAdminPrompt))
        if case .succeeded = nextSetResult {
            sleepDisabled = disabled
            if disabled && allowAdminPrompt {
                passwordlessHelper = true
            }
        }
        return nextSetResult
    }

    func installPasswordlessHelper() -> StayAwakePrivilegedResult {
        if case .succeeded = nextInstallResult {
            passwordlessHelper = true
        }
        return nextInstallResult
    }

    func removePasswordlessHelper() -> StayAwakePrivilegedResult {
        if case .succeeded = nextRemoveResult {
            passwordlessHelper = false
            sleepDisabled = false
        }
        return nextRemoveResult
    }

    func acquireIdleAssertion(preventDisplaySleep: Bool) -> Bool {
        assertionCalls.append(preventDisplaySleep)
        return true
    }

    func releaseIdleAssertion() {
        releaseCalls += 1
    }

    func readPowerSnapshot() -> StayAwakePowerSnapshot { powerSnapshot }

    func startPowerSourceObserver(_ handler: @escaping @Sendable () -> Void) {
        observerStartCalls += 1
        activePowerHandler = handler
    }

    func stopPowerSourceObserver() {
        observerStopCalls += 1
        activePowerHandler = nil
    }
}

// MARK: - Tests

@MainActor
final class StayAwakeTests: XCTestCase {
    private func makeSettings() -> AppSettings {
        let suite = "prompt-annotator.stayawake.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        return AppSettings(defaults: defaults)
    }

    // MARK: - Sudoers Rule & Parsers

    func testUsernameValidationRejectsShellInjection() {
        XCTAssertTrue(StayAwakeSudoersRule.isValidUsername("pbrown"))
        XCTAssertTrue(StayAwakeSudoersRule.isValidUsername("jane.doe_01-mac"))
        XCTAssertFalse(StayAwakeSudoersRule.isValidUsername(""))
        XCTAssertFalse(StayAwakeSudoersRule.isValidUsername("root; rm -rf /"))
        XCTAssertFalse(StayAwakeSudoersRule.isValidUsername("user name"))
        XCTAssertFalse(StayAwakeSudoersRule.isValidUsername("user\nALL=(ALL) NOPASSWD: ALL"))
        XCTAssertFalse(StayAwakeSudoersRule.isValidUsername("user'quote"))
    }

    func testSudoersRuleIsStrictlyScopedToPmsetDisableSleep() {
        let content = StayAwakeSudoersRule.ruleContent(for: "pbrown")
        XCTAssertEqual(
            content,
            "# Managed by da transcribuh (closed-lid stay awake)\npbrown ALL=(root) NOPASSWD: /usr/bin/pmset -a disablesleep 0, /usr/bin/pmset -a disablesleep 1\n"
        )
        XCTAssertNil(StayAwakeSudoersRule.ruleContent(for: "bad user"))
    }

    func testInstallCommandValidatesWithVisudoBeforeAtomicMove() {
        let cmd = StayAwakeSudoersRule.installCommand(username: "pbrown", setSleepDisabled: true)
        XCTAssertNotNil(cmd)
        XCTAssertTrue(cmd!.contains("set -e"))
        XCTAssertTrue(cmd!.contains("/usr/sbin/visudo -cf \"$TMP\""))
        XCTAssertTrue(cmd!.contains("/bin/chmod 0440 \"$TMP\""))
        XCTAssertTrue(cmd!.contains("/usr/sbin/chown root:wheel \"$TMP\""))
        XCTAssertTrue(cmd!.contains("/bin/mv -f \"$TMP\" '/etc/sudoers.d/da-transcribuh-sleep'"))
        XCTAssertTrue(cmd!.contains("/usr/bin/pmset -a disablesleep 1"))
    }

    func testAppleScriptQuotingEscapesQuotesAndBackslashes() {
        let script = StayAwakeSudoersRule.appleScriptCommand(
            shellScript: "printf \"%s\\n\" \"$TMP\"",
            prompt: "Allow \"da transcribuh\""
        )
        XCTAssertEqual(
            script,
            "do shell script \"printf \\\"%s\\\\n\\\" \\\"$TMP\\\"\" with prompt \"Allow \\\"da transcribuh\\\"\" with administrator privileges"
        )
    }

    func testParsePmsetSleepDisabled() {
        let onOutput = """
        System-wide power settings:
         SleepDisabled\t\t1
        Currently in use:
         sleep                1
        """
        let offOutput = """
        System-wide power settings:
         SleepDisabled\t\t0
        Currently in use:
         sleep                1
        """
        let missingOutput = """
        System-wide power settings:
        Currently in use:
         sleep                1
        """
        XCTAssertTrue(StayAwakeSudoersRule.parsePmsetSleepDisabled(onOutput))
        XCTAssertFalse(StayAwakeSudoersRule.parsePmsetSleepDisabled(offOutput))
        XCTAssertFalse(StayAwakeSudoersRule.parsePmsetSleepDisabled(missingOutput))
    }

    func testFormatRemaining() {
        XCTAssertEqual(StayAwakeSudoersRule.formatRemaining(12), "<1m left")
        XCTAssertEqual(StayAwakeSudoersRule.formatRemaining(60), "1m left")
        XCTAssertEqual(StayAwakeSudoersRule.formatRemaining(3540), "59m left")
        XCTAssertEqual(StayAwakeSudoersRule.formatRemaining(3600), "1h left")
        XCTAssertEqual(StayAwakeSudoersRule.formatRemaining(5400), "1h 30m left")
    }

    // MARK: - Mode Transitions

    func testEnableLidClosedSetsPmsetAndSystemAssertion() async {
        let bridge = FakeStayAwakeBridge()
        let settings = makeSettings()
        let controller = StayAwakeController(bridge: bridge, settings: settings)

        await controller.setMode(.lidClosed)

        XCTAssertEqual(controller.mode, .lidClosed)
        XCTAssertTrue(controller.isActive)
        XCTAssertEqual(controller.indicatorState, .lidClosed)
        XCTAssertTrue(bridge.sleepDisabled)
        XCTAssertTrue(controller.helperInstalled)
        XCTAssertEqual(bridge.setCalls.count, 1)
        XCTAssertEqual(bridge.setCalls.first?.disabled, true)
        XCTAssertEqual(bridge.assertionCalls, [false]) // allow display to dim while lid is closed
    }

    func testEnableLidOpenDoesNotTouchPmset() async {
        let bridge = FakeStayAwakeBridge()
        let settings = makeSettings()
        let controller = StayAwakeController(bridge: bridge, settings: settings)

        await controller.setMode(.lidOpen)

        XCTAssertEqual(controller.mode, .lidOpen)
        XCTAssertEqual(controller.indicatorState, .lidOpen)
        XCTAssertTrue(bridge.setCalls.isEmpty)
        XCTAssertEqual(bridge.assertionCalls, [true]) // keep display awake too when lid is open
    }

    func testSwitchingLidClosedToLidOpenRestoresPmset() async {
        let bridge = FakeStayAwakeBridge()
        let settings = makeSettings()
        let controller = StayAwakeController(bridge: bridge, settings: settings)

        await controller.setMode(.lidClosed)
        await controller.setMode(.lidOpen)

        XCTAssertEqual(controller.mode, .lidOpen)
        XCTAssertFalse(bridge.sleepDisabled)
        XCTAssertEqual(bridge.setCalls.map(\.disabled), [true, false])
        XCTAssertEqual(bridge.assertionCalls, [false, true])
    }

    func testCancelledAdminPromptLeavesModeOffWithNoError() async {
        let bridge = FakeStayAwakeBridge()
        bridge.nextSetResult = .cancelled
        let settings = makeSettings()
        let controller = StayAwakeController(bridge: bridge, settings: settings)

        await controller.setMode(.lidClosed)

        XCTAssertEqual(controller.mode, .off)
        XCTAssertFalse(controller.isActive)
        XCTAssertNil(controller.statusMessage)
        XCTAssertFalse(controller.statusIsError)
    }

    func testFailedAdminPromptSurfacesErrorAndLeavesModeOff() async {
        let bridge = FakeStayAwakeBridge()
        bridge.nextSetResult = .failed("Permission denied")
        let settings = makeSettings()
        let controller = StayAwakeController(bridge: bridge, settings: settings)

        await controller.setMode(.lidClosed)

        XCTAssertEqual(controller.mode, .off)
        XCTAssertEqual(controller.statusMessage, "Permission denied")
        XCTAssertTrue(controller.statusIsError)
    }

    // MARK: - External State Sync

    func testRefreshDetectsExternalSleepDisabledAndDisableClearsIt() async {
        let bridge = FakeStayAwakeBridge()
        bridge.sleepDisabled = true
        let settings = makeSettings()
        let controller = StayAwakeController(bridge: bridge, settings: settings)

        controller.refreshSystemState()

        XCTAssertEqual(controller.mode, .off)
        XCTAssertTrue(controller.externallyDisabled)
        XCTAssertTrue(controller.isActive)
        XCTAssertEqual(controller.indicatorState, .lidClosed)
        XCTAssertTrue(controller.menuStatusLine.contains("externally"))

        await controller.setMode(.off)

        XCTAssertFalse(controller.externallyDisabled)
        XCTAssertFalse(controller.isActive)
        XCTAssertFalse(bridge.sleepDisabled)
        XCTAssertEqual(bridge.setCalls.last?.disabled, false)
    }

    func testRefreshSyncsToOffWhenExternalToolClearsSleepDisabled() async {
        let bridge = FakeStayAwakeBridge()
        let settings = makeSettings()
        let controller = StayAwakeController(bridge: bridge, settings: settings)

        await controller.setMode(.lidClosed)
        bridge.sleepDisabled = false
        controller.refreshSystemState()

        XCTAssertEqual(controller.mode, .off)
        XCTAssertFalse(controller.isActive)
    }

    // MARK: - Timer & Battery Cutoff

    func testTimerExpiryAutomaticallyDisablesStayAwake() async {
        let bridge = FakeStayAwakeBridge()
        let settings = makeSettings()
        var current = Date(timeIntervalSince1970: 1_700_000_000)
        let controller = StayAwakeController(bridge: bridge, settings: settings, now: { current })

        controller.setDuration(.oneHour)
        await controller.setMode(.lidClosed)
        XCTAssertEqual(controller.remainingText, "1h left")

        current = current.addingTimeInterval(1800)
        controller.evaluateSafetyAndTimer()
        XCTAssertEqual(controller.remainingText, "30m left")
        XCTAssertEqual(controller.mode, .lidClosed)

        current = current.addingTimeInterval(1801)
        controller.evaluateSafetyAndTimer()
        try? await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertEqual(controller.mode, .off)
        XCTAssertFalse(bridge.sleepDisabled)
        XCTAssertEqual(controller.statusMessage, "Timer ended")
    }

    func testBatteryCutoffDisablesOnBatteryButNotWhenPluggedIn() async {
        let bridge = FakeStayAwakeBridge()
        bridge.powerSnapshot = StayAwakePowerSnapshot(hasBattery: true, onBattery: false, batteryPercent: 15)
        let settings = makeSettings()
        settings.setStayAwakeBatteryCutoff(20)
        let controller = StayAwakeController(bridge: bridge, settings: settings)

        await controller.setMode(.lidClosed)
        // Plugged in at 15% — should stay active.
        controller.evaluateSafetyAndTimer()
        try? await Task.sleep(nanoseconds: 30_000_000)
        XCTAssertEqual(controller.mode, .lidClosed)

        // Unplugged at 15% (<= 20% cutoff) — must auto-disable.
        bridge.powerSnapshot = StayAwakePowerSnapshot(hasBattery: true, onBattery: true, batteryPercent: 15)
        controller.evaluateSafetyAndTimer()
        try? await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertEqual(controller.mode, .off)
        XCTAssertFalse(bridge.sleepDisabled)
        XCTAssertEqual(controller.statusMessage, "Stopped at 15% battery")
    }

    func testManualStartBelowCutoffShowsWarningAndRespectsCriticalFloor() async {
        let bridge = FakeStayAwakeBridge()
        bridge.powerSnapshot = StayAwakePowerSnapshot(hasBattery: true, onBattery: true, batteryPercent: 16)
        let settings = makeSettings()
        settings.setStayAwakeBatteryCutoff(20)
        let controller = StayAwakeController(bridge: bridge, settings: settings)

        await controller.setMode(.lidClosed)
        XCTAssertEqual(controller.mode, .lidClosed)
        XCTAssertEqual(controller.statusMessage, "Low battery (16%) — plug in soon")

        // Stays on at 12% since user deliberately started below 20%.
        bridge.powerSnapshot = StayAwakePowerSnapshot(hasBattery: true, onBattery: true, batteryPercent: 12)
        controller.evaluateSafetyAndTimer()
        try? await Task.sleep(nanoseconds: 30_000_000)
        XCTAssertEqual(controller.mode, .lidClosed)

        // Drops to critical 5% floor — auto-disables for safety.
        bridge.powerSnapshot = StayAwakePowerSnapshot(hasBattery: true, onBattery: true, batteryPercent: 5)
        controller.evaluateSafetyAndTimer()
        try? await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertEqual(controller.mode, .off)
        XCTAssertFalse(bridge.sleepDisabled)
    }

    // MARK: - Quit Cleanup

    func testShutdownRestoresSleepWithoutPromptWhenOwnedAndEnabled() async {
        let bridge = FakeStayAwakeBridge()
        let settings = makeSettings()
        settings.setStayAwakeRestoreOnQuit(true)
        let controller = StayAwakeController(bridge: bridge, settings: settings)

        await controller.setMode(.lidClosed)
        controller.shutdown()

        XCTAssertEqual(controller.mode, .off)
        XCTAssertFalse(bridge.sleepDisabled)
        XCTAssertEqual(bridge.setCalls.last?.disabled, false)
        XCTAssertEqual(bridge.setCalls.last?.allowAdminPrompt, false)
    }

    func testShutdownLeavesSleepDisabledWhenRestoreOnQuitIsOff() async {
        let bridge = FakeStayAwakeBridge()
        let settings = makeSettings()
        settings.setStayAwakeRestoreOnQuit(false)
        let controller = StayAwakeController(bridge: bridge, settings: settings)

        await controller.setMode(.lidClosed)
        controller.shutdown()

        XCTAssertTrue(bridge.sleepDisabled)
        XCTAssertEqual(bridge.setCalls.count, 1) // only the enable call
    }

    // MARK: - Settings Persistence & Search

    func testStayAwakeSettingsPersistAcrossInstances() {
        let suite = "prompt-annotator.stayawake.persist.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!

        let first = AppSettings(defaults: defaults)
        XCTAssertEqual(first.stayAwakeDefaultMode, .lidClosed)
        XCTAssertEqual(first.stayAwakeDefaultDuration, .indefinite)
        XCTAssertEqual(first.stayAwakeBatteryCutoff, 20)
        XCTAssertTrue(first.stayAwakeRestoreOnQuit)

        first.setStayAwakeDefaultMode(.lidOpen)
        first.setStayAwakeDefaultDuration(.twoHours)
        first.setStayAwakeBatteryCutoff(30)
        first.setStayAwakeRestoreOnQuit(false)

        let second = AppSettings(defaults: defaults)
        XCTAssertEqual(second.stayAwakeDefaultMode, .lidOpen)
        XCTAssertEqual(second.stayAwakeDefaultDuration, .twoHours)
        XCTAssertEqual(second.stayAwakeBatteryCutoff, 30)
        XCTAssertFalse(second.stayAwakeRestoreOnQuit)
    }

    func testSettingsSearchFindsStayAwake() {
        let hits = SettingsSearch.search(query: "lid is closed", sessions: [], modelTitles: [])
        XCTAssertEqual(hits.first?.page, .configuration)
        XCTAssertEqual(hits.first?.highlightTitle, "Stay awake mode")
    }

    // MARK: - Menu Bar Status Icon Rendering

    func testMenuBarStatusIconRendersColoredBadgeForActiveStates() throws {
        XCTAssertNil(MenuBarStatusIcon.image(for: .inactive))

        let lidClosed = try XCTUnwrap(MenuBarStatusIcon.image(for: .lidClosed))
        XCTAssertFalse(lidClosed.isTemplate)
        XCTAssertEqual(lidClosed.size, MenuBarStatusIcon.activeCanvasSize)

        let lidOpen = try XCTUnwrap(MenuBarStatusIcon.image(for: .lidOpen))
        XCTAssertFalse(lidOpen.isTemplate)

        // Verify orange pixels appear in both icon & badge regions for `.lidClosed`.
        let rep = try XCTUnwrap(MenuBarStatusIcon.renderBitmap(for: .lidClosed, darkMenuBar: true, scale: 2))
        let badgePixel = try XCTUnwrap(rep.colorAt(x: 37, y: 8)) // badge center in 42x32 top-down coords
        XCTAssertGreaterThan(badgePixel.alphaComponent, 0.8)
        XCTAssertGreaterThan(badgePixel.redComponent, 0.8)
        XCTAssertGreaterThan(badgePixel.greenComponent, 0.4)
        XCTAssertLessThan(badgePixel.blueComponent, 0.4)

        // Verify green pixels appear for `.lidOpen`.
        let greenRep = try XCTUnwrap(MenuBarStatusIcon.renderBitmap(for: .lidOpen, darkMenuBar: true, scale: 2))
        let greenBadge = try XCTUnwrap(greenRep.colorAt(x: 37, y: 8))
        XCTAssertGreaterThan(greenBadge.alphaComponent, 0.8)
        XCTAssertGreaterThan(greenBadge.greenComponent, 0.6)
        XCTAssertLessThan(greenBadge.redComponent, 0.5)
    }

    func testRenderStayAwakeVisualSnapshots() async throws {
        guard let dir = ProcessInfo.processInfo.environment["DTStayAwakeSnapDir"], !dir.isEmpty else {
            throw XCTSkip("Set DTStayAwakeSnapDir to render visual snapshots.")
        }
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        InkFontRegistrar.registerBundledFonts()

        // 1. Render dark/light menu bar icon comparisons (normal, lidClosed, lidOpen).
        for (label, dark) in [("dark", true), ("light", false)] {
            for (stateName, state) in [("lidClosed", StayAwakeIndicatorState.lidClosed), ("lidOpen", .lidOpen)] {
                if let rep = MenuBarStatusIcon.renderBitmap(for: state, darkMenuBar: dark, scale: 2),
                   let data = rep.representation(using: .png, properties: [:]) {
                    try data.write(to: URL(fileURLWithPath: "\(dir)/icon-\(stateName)-\(label).png"))
                }
            }
        }

        // 2. Render DTMenuBarPanel in OFF and ACTIVE (lidClosed) states.
        let bridge = FakeStayAwakeBridge()
        bridge.powerSnapshot = StayAwakePowerSnapshot(hasBattery: true, onBattery: true, batteryPercent: 84)
        let settings = makeSettings()
        let controller = StayAwakeController(bridge: bridge, settings: settings)

        renderPanel(controller: controller, settings: settings, appearance: .darkAqua, path: "\(dir)/panel-off-dark.png")
        controller.setDuration(.twoHours)
        await controller.setMode(.lidClosed)
        renderPanel(controller: controller, settings: settings, appearance: .darkAqua, path: "\(dir)/panel-on-dark.png")
        renderPanel(controller: controller, settings: settings, appearance: .aqua, path: "\(dir)/panel-on-light.png")
    }

    private func renderPanel(
        controller: StayAwakeController,
        settings: AppSettings,
        appearance: NSAppearance.Name,
        path: String
    ) {
        NSApp.appearance = NSAppearance(named: appearance)
        let view = DTMenuBarPanel(
            session: SessionController.shared,
            settings: settings,
            stayAwake: controller
        )
        let host = NSHostingView(rootView: view)
        host.appearance = NSAppearance(named: appearance)
        let size = host.fittingSize
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: appearance)
        window.backgroundColor = .clear
        window.isOpaque = false
        window.alphaValue = 0
        window.ignoresMouseEvents = true
        window.contentView = host
        window.setContentSize(size)
        window.setFrameOrigin(NSPoint(x: -30_000, y: -30_000))
        window.orderBack(nil)
        host.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))
        if let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) {
            host.cacheDisplay(in: host.bounds, to: rep)
            try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
        }
        window.orderOut(nil)
        window.close()
    }
}
