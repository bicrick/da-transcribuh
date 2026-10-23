import AppKit
import AVFoundation
import Darwin
import Foundation
import QuartzCore

/// Launch-argument measurement harness (see docs/perf-audit.md). Nothing here runs
/// without one of its `-DTPerf…` arguments. Session harnesses never touch the user's
/// clipboard, sessions folder, sounds or paste target.
///
/// - `-DTPerfLaunch YES` logs launch milestones in ms since process start.
/// - `-DTPerfSpeech a.wav,b.wav` feeds each file through the capture pipeline in real
///   time and logs stop -> clipboard latency. `-DTPerfSpeechRuns N`, `-DTPerfLive NO`.
/// - `-DTPerfPaste YES` (with `-DTPerfSpeech`) runs the real paste path into the app named
///   by `-DTPerfPasteTarget` (bundle id) and logs stop -> ⌘V and stop -> text landed. The
///   target appends `landed <systemUptime>` lines to `-DTPerfPasteLog`. The general
///   pasteboard is snapshotted first and restored at the end.
/// - `-DTPerfTailJitterMs N` adds a random 0…N ms to the tail before each stop, so the stop
///   lands at a random point of the live-decode cycle (as a person's stop does).
/// - `-DTPerfRecStart N` starts and cancels N real-mic sessions and logs start latency.
/// - `-DTPerfPanelType text` / `-DTPerfPanelScroll N` extend `-DTPerfPanel`.
/// - `-DTPerfSeedClipboard N` fills a `-DTClipboardRoot` store with N items.
/// - `-DTSessionsRoot path`, `-DTClipboardRoot path` redirect storage.
@MainActor
enum PerfSuite {
    private static var args: UserDefaults { .standard }

    static var launch: Bool { args.bool(forKey: "DTPerfLaunch") }
    static var speechFiles: [String] {
        (args.string(forKey: "DTPerfSpeech") ?? "").split(separator: ",").map(String.init)
    }
    static var recStartRuns: Int { args.integer(forKey: "DTPerfRecStart") }
    static var isActive: Bool {
        launch || !speechFiles.isEmpty || recStartRuns > 0 || args.integer(forKey: "DTPerfIdle") > 0
    }

    /// Session harnesses run isolated from the user's clipboard and paste target.
    nonisolated static var isolatesSession: Bool {
        let d = UserDefaults.standard
        return !(d.string(forKey: "DTPerfSpeech") ?? "").isEmpty || d.integer(forKey: "DTPerfRecStart") > 0
    }

    /// `-DTPerfPaste YES`: the speech harness pastes into its own target app.
    nonisolated static var pasteMode: Bool {
        UserDefaults.standard.bool(forKey: "DTPerfPaste")
    }

    nonisolated static var liveDecodeDisabled: Bool {
        UserDefaults.standard.object(forKey: "DTPerfLive") != nil && !UserDefaults.standard.bool(forKey: "DTPerfLive")
    }

    nonisolated static var sessionsRootOverride: URL? {
        UserDefaults.standard.string(forKey: "DTSessionsRoot").map { URL(fileURLWithPath: $0, isDirectory: true) }
    }

    nonisolated static var clipboardRootOverride: URL? {
        UserDefaults.standard.string(forKey: "DTClipboardRoot").map { URL(fileURLWithPath: $0, isDirectory: true) }
    }

    /// The board session output goes to. A private named board under a harness.
    static var sessionPasteboard: NSPasteboard {
        isolatesSession && !pasteMode
            ? NSPasteboard(name: NSPasteboard.Name("com.bicrick.PromptAnnotator.perf"))
            : .general
    }

    static func log(_ line: String) {
        FileHandle.standardError.write(Data(("dtperf " + line + "\n").utf8))
    }

    // MARK: - Clocks

    /// Process start from the kernel, in Unix seconds.
    static let processStart: Double = {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()]
        guard sysctl(&mib, 4, &info, &size, nil, 0) == 0 else { return Date().timeIntervalSince1970 }
        let tv = info.kp_proc.p_starttime
        return Double(tv.tv_sec) + Double(tv.tv_usec) / 1_000_000
    }()

    static func msSinceProcessStart() -> Double {
        (Date().timeIntervalSince1970 - processStart) * 1000
    }

    /// Physical footprint (what Activity Monitor calls Memory), MB.
    nonisolated static func footprintMB() -> Double {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let kr = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        return kr == KERN_SUCCESS ? Double(info.phys_footprint) / 1_048_576 : -1
    }

    /// User + system CPU seconds for this process.
    nonisolated static func cpuSeconds() -> Double {
        var usage = rusage()
        getrusage(RUSAGE_SELF, &usage)
        let user = Double(usage.ru_utime.tv_sec) + Double(usage.ru_utime.tv_usec) / 1e6
        let sys = Double(usage.ru_stime.tv_sec) + Double(usage.ru_stime.tv_usec) / 1e6
        return user + sys
    }

    /// Calls `work` at the first run-loop sleep after Core Animation commits.
    static func afterDisplay(_ work: @escaping @MainActor () -> Void) {
        let observer = CFRunLoopObserverCreateWithHandler(
            kCFAllocatorDefault, CFRunLoopActivity.beforeWaiting.rawValue, false, 3_000_000
        ) { _, _ in
            MainActor.assumeIsolated { work() }
        }
        CFRunLoopAddObserver(CFRunLoopGetMain(), observer, .commonModes)
    }

    private static func sleep(ms: Double) async {
        try? await Task.sleep(nanoseconds: UInt64(max(0, ms) * 1_000_000))
    }

    // MARK: - Frame pacing

    private static var paceLast: [String: CFTimeInterval] = [:]
    private static var paceGaps: [String: [Double]] = [:]

    /// Records the gap since the previous call for `key` (timer-driven animations).
    static func pace(_ key: String) {
        guard isActive else { return }
        let now = CACurrentMediaTime()
        if let last = paceLast[key], now - last < 0.5 {
            paceGaps[key, default: []].append((now - last) * 1000)
        }
        paceLast[key] = now
    }

    static func flushPace() {
        for (key, gaps) in paceGaps.sorted(by: { $0.key < $1.key }) where !gaps.isEmpty {
            let sorted = gaps.sorted()
            let p50 = sorted[sorted.count / 2]
            let p95 = sorted[min(sorted.count - 1, Int(Double(sorted.count) * 0.95))]
            let late = gaps.filter { $0 > 25 }.count
            log(String(format: "pace %@ n=%d p50=%.1f p95=%.1f max=%.1f over25=%d",
                       key, gaps.count, p50, p95, sorted.last ?? 0, late))
        }
        paceGaps = [:]
        paceLast = [:]
        if !counts.isEmpty {
            log("counts " + counts.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: " "))
            counts = [:]
        }
    }

    private static var counts: [String: Int] = [:]
    /// Counts body evaluations and similar events between flushes. Cheap no-op unless measuring.
    static func count(_ key: String) {
        guard isActive else { return }
        counts[key, default: 0] += 1
    }

    // MARK: - Session stamps

    private static var clipboardStamp: CFTimeInterval = 0
    private static var stopStamp: CFTimeInterval = 0
    private static var stopPhases: [String] = []

    /// Splits stop → clipboard into named phases (harness only).
    static func stopMark(_ label: String) {
        guard isolatesSession, stopStamp > 0 else { return }
        stopPhases.append(String(format: "%@=%.0f", label, (CACurrentMediaTime() - stopStamp) * 1000))
    }
    static func markClipboardWritten() {
        guard isolatesSession else { return }
        clipboardStamp = CACurrentMediaTime()
    }

    // MARK: - Entry

    static func start() {
        if launch { runLaunch() }
        seedClipboardIfRequested()
        if !speechFiles.isEmpty { Task { await runSpeech() } }
        if recStartRuns > 0 { Task { await runRecStart() } }
        let ingest = args.integer(forKey: "DTPerfClipIngest")
        if ingest > 0 { Task { await runClipIngest(ingest) } }
        if args.bool(forKey: "DTPerfCloseSettings") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                SettingsPresenter.shared.attachedWindow?.orderOut(nil)
                log("settings closed")
            }
        }
        let idle = args.integer(forKey: "DTPerfIdle")
        if idle > 0 {
            Task {
                await sleep(ms: 15_000)
                let c0 = cpuSeconds()
                let t0 = CACurrentMediaTime()
                await sleep(ms: Double(idle) * 1000)
                let wall = CACurrentMediaTime() - t0
                log(String(format: "idle cpu=%.2f%% footprint=%.1fMB window=%.0fs",
                           (cpuSeconds() - c0) / wall * 100, footprintMB(), wall))
                quitIfRequested()
            }
        }
    }

    private static func quitIfRequested() {
        log("done")
        if args.bool(forKey: "DTPerfQuit") { NSApp.terminate(nil) }
    }

    // MARK: - Launch

    static func launchMark(_ label: String) {
        guard launch else { return }
        log(String(format: "launch %@ %.1f", label, msSinceProcessStart()))
    }

    private static func runLaunch() {
        afterDisplay { launchMark("firstCommit") }
        Task {
            var menubar = false
            var settings = false
            var model = false
            let deadline = CACurrentMediaTime() + 120
            while CACurrentMediaTime() < deadline, !(menubar && settings && model) {
                if !menubar, NSApp.windows.contains(where: {
                    String(describing: type(of: $0)).contains("StatusBarWindow") && $0.isVisible
                }) {
                    menubar = true
                    launchMark("menubarReady")
                }
                if !settings, let window = SettingsPresenter.shared.attachedWindow,
                   window.occlusionState.contains(.visible) {
                    settings = true
                    launchMark("settingsVisible")
                }
                if !model, WhisperKitTranscriber.isModelReady {
                    model = true
                    launchMark("modelReady")
                    log(String(format: "launch footprintModelReady %.1f", footprintMB()))
                }
                await sleep(ms: 5)
            }
            await sleep(ms: 300)
            quitIfRequested()
        }
    }

    // MARK: - Speech (WAV feed)

    private static func runSpeech() async {
        let session = SessionController.shared
        let outDir = URL(fileURLWithPath: args.string(forKey: "DTPerfOut") ?? "/tmp/dtperf-out", isDirectory: true)
        try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
        let firstWait = CACurrentMediaTime()
        // AppDelegate starts prepareModel after 450 ms. Wait for it so run 1 is not a cold load
        // unless `-DTPerfColdModel YES` asks to measure exactly that.
        if !args.bool(forKey: "DTPerfColdModel") {
            while !WhisperKitTranscriber.isModelReady, CACurrentMediaTime() - firstWait < 180 {
                await sleep(ms: 20)
            }
            log(String(format: "speech modelReady %.1f footprint=%.1fMB", msSinceProcessStart(), footprintMB()))
            await sleep(ms: 1500)
        }
        let runs = max(1, args.integer(forKey: "DTPerfSpeechRuns"))
        let basePad = Double(args.object(forKey: "DTPerfTailMs") as? Int ?? 400)
        let jitter = max(0, args.integer(forKey: "DTPerfTailJitterMs"))
        let live = !liveDecodeDisabled
        let paste = pasteMode
        let targetID = args.string(forKey: "DTPerfPasteTarget") ?? "com.bicrick.dtpastetarget"
        let landedLog = URL(fileURLWithPath: args.string(forKey: "DTPerfPasteLog") ?? "/tmp/dtpaste-landed.txt")
        var savedBoard: [NSPasteboardItem] = []
        if paste {
            savedBoard = snapshotGeneralPasteboard()
            log("paste trusted=\(AXIsProcessTrusted()) target=\(targetID)")
        }
        for run in 1...runs {
            for path in speechFiles {
                let url = URL(fileURLWithPath: path)
                guard let file = try? AVAudioFile(forReading: url) else {
                    log("speech missing \(path)")
                    continue
                }
                let seconds = Double(file.length) / file.processingFormat.sampleRate
                AudioRecorder.feedURL = url
                flushPace()
                let b0 = CACurrentMediaTime()
                await session.perfBegin()
                let beginMs = (CACurrentMediaTime() - b0) * 1000
                guard session.phase == .recording else {
                    log("speech begin failed phase=\(session.phase)")
                    AudioRecorder.feedURL = nil
                    if paste { restoreGeneralPasteboard(savedBoard) }
                    quitIfRequested()
                    return
                }
                let c0 = cpuSeconds()
                let r0 = CACurrentMediaTime()
                let pad = basePad + (jitter > 0 ? Double(Int.random(in: 0...jitter)) : 0)
                if paste {
                    activate(targetID)
                }
                await sleep(ms: seconds * 1000 + pad)
                let recCPU = (cpuSeconds() - c0) / (CACurrentMediaTime() - r0) * 100
                let recMem = footprintMB()
                var peak = recMem
                let sampler = Task { @MainActor in
                    while !Task.isCancelled {
                        peak = max(peak, footprintMB())
                        await sleep(ms: 20)
                    }
                }
                clipboardStamp = 0
                let board = sessionPasteboard
                board.clearContents()
                let s0 = CACurrentMediaTime()
                let sc0 = cpuSeconds()
                stopStamp = s0
                stopPhases = []
                let u0 = ProcessInfo.processInfo.systemUptime
                var frontmost = ""
                var flagsBefore: UInt64 = 0
                if paste {
                    frontmost = NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "?"
                    flagsBefore = CGEventSource.flagsState(.hidSystemState).rawValue
                    StopTrace.noteTrigger(uptime: u0)
                }
                await session.perfFinish()
                stopStamp = 0
                if paste {
                    let w0 = CACurrentMediaTime()
                    while StopTrace.isOpen, CACurrentMediaTime() - w0 < 2 {
                        await sleep(ms: 2)
                    }
                    // Give the target app time to receive and apply the paste.
                    await sleep(ms: 600)
                    let landed = lastLanded(in: landedLog)
                    let landMs = landed > u0 ? (landed - u0) * 1000 : -1
                    let flagsAfter = CGEventSource.flagsState(.hidSystemState).rawValue
                    log(String(format: "paste %@ run=%d pad=%.0f front=%@ stop2paste=%.1f stop2land=%.1f flags=%llx>%llx",
                               url.deletingPathExtension().lastPathComponent, run, pad, frontmost,
                               StopTrace.lastPasteMs ?? -1, landMs, flagsBefore, flagsAfter))
                }
                if let summary = StopTrace.lastSummary {
                    log("stoptrace " + summary)
                }
                let idleMs = (CACurrentMediaTime() - s0) * 1000
                let stopCPU = cpuSeconds() - sc0
                sampler.cancel()
                peak = max(peak, footprintMB())
                let clipMs = clipboardStamp > 0 ? (clipboardStamp - s0) * 1000 : -1
                let text = board.string(forType: .string) ?? ""
                let name = url.deletingPathExtension().lastPathComponent
                try? text.write(to: outDir.appendingPathComponent("\(name)-\(live ? "live" : "final")-r\(run).txt"),
                                atomically: true, encoding: .utf8)
                log(String(format: "speech %@ run=%d live=%@ audio=%.1fs begin=%.1f stop2clip=%.1f stop2idle=%.1f recCPU=%.1f%% stopCPU=%.2fs recMB=%.1f peakMB=%.1f words=%d",
                           name, run, live ? "YES" : "NO", seconds, beginMs, clipMs, idleMs, recCPU, stopCPU,
                           recMem, peak, text.split(separator: " ").count))
                log("stopphases \(name) run=\(run) " + stopPhases.joined(separator: " "))
                flushPace()
                AudioRecorder.feedURL = nil
                await sleep(ms: 1200)
            }
        }
        if paste { restoreGeneralPasteboard(savedBoard) }
        quitIfRequested()
    }

    private static func activate(_ bundleID: String) {
        NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first?
            .activate(options: [.activateAllWindows])
    }

    /// Last `landed <uptime>` stamp the paste target wrote.
    private static func lastLanded(in url: URL) -> TimeInterval {
        guard let text = try? String(contentsOf: url, encoding: .utf8),
              let line = text.split(separator: "\n").last(where: { $0.hasPrefix("landed ") }),
              let field = line.split(separator: " ").dropFirst().first,
              let value = Double(field) else { return 0 }
        return value
    }

    private static func snapshotGeneralPasteboard() -> [NSPasteboardItem] {
        (NSPasteboard.general.pasteboardItems ?? []).map { item in
            let copy = NSPasteboardItem()
            for type in item.types {
                if let data = item.data(forType: type) { copy.setData(data, forType: type) }
            }
            return copy
        }
    }

    private static func restoreGeneralPasteboard(_ items: [NSPasteboardItem]) {
        NSPasteboard.general.clearContents()
        if !items.isEmpty { NSPasteboard.general.writeObjects(items) }
    }

    // MARK: - Recording start (real microphone)

    private static func runRecStart() async {
        let session = SessionController.shared
        await sleep(ms: Double(args.object(forKey: "DTPerfDelayMs") as? Int ?? 3000))
        for run in 1...recStartRuns {
            AudioRecorder.resetFirstBufferStamp()
            let b0 = CACurrentMediaTime()
            await session.perfBegin()
            let beginMs = (CACurrentMediaTime() - b0) * 1000
            guard session.phase == .recording else {
                log("recstart begin failed phase=\(session.phase)")
                break
            }
            var displayMs = -1.0
            afterDisplay { displayMs = (CACurrentMediaTime() - b0) * 1000 }
            var audioMs = -1.0
            let wait0 = CACurrentMediaTime()
            while CACurrentMediaTime() - wait0 < 2 {
                let stamp = AudioRecorder.firstBufferStamp()
                if stamp > 0 {
                    audioMs = (stamp - b0) * 1000
                    break
                }
                await sleep(ms: 2)
            }
            let c0 = cpuSeconds()
            let t0 = CACurrentMediaTime()
            await sleep(ms: 1500)
            let recCPU = (cpuSeconds() - c0) / (CACurrentMediaTime() - t0) * 100
            log(String(format: "recstart run=%d begin=%.1f islandCommit=%.1f firstAudio=%.1f recCPU=%.1f%%",
                       run, beginMs, displayMs, audioMs, recCPU))
            flushPace()
            session.cancel()
            await sleep(ms: 1200)
        }
        quitIfRequested()
    }

    // MARK: - Clipboard panel extras

    /// Types `-DTPerfPanelType` into the open panel, one key per 120 ms, then
    /// scrolls the list `-DTPerfPanelScroll` steps. Each step logs a `dtperf` line.
    static func panelExtras(then done: @escaping @MainActor () -> Void) {
        let text = Array(args.string(forKey: "DTPerfPanelType") ?? "")
        let steps = args.integer(forKey: "DTPerfPanelScroll")
        Task {
            let window = ClipboardHistoryPanelController.shared.window
            for (index, ch) in text.enumerated() {
                let s = String(ch)
                PerfProbe.begin("type", "\(index + 1)")
                if let event = NSEvent.keyEvent(
                    with: .keyDown, location: .zero, modifierFlags: [],
                    timestamp: ProcessInfo.processInfo.systemUptime,
                    windowNumber: window?.windowNumber ?? 0, context: nil,
                    characters: s, charactersIgnoringModifiers: s, isARepeat: false, keyCode: 0
                ) {
                    NSApp.postEvent(event, atStart: false)
                }
                await sleep(ms: 120)
            }
            if !text.isEmpty {
                // Clear the query again so the scroll runs over the full list.
                for _ in text { postKey(51, window: window) ; await sleep(ms: 60) }
                await sleep(ms: 300)
            }
            if steps > 0, let scroll = window?.contentView.flatMap(findScrollView) {
                for _ in 0..<steps {
                    let clip = scroll.contentView
                    let maxY = max(0, (scroll.documentView?.frame.height ?? 0) - clip.bounds.height)
                    var y = clip.bounds.origin.y + 40
                    if y > maxY { y = 0 }
                    let t0 = CACurrentMediaTime()
                    clip.scroll(to: NSPoint(x: 0, y: y))
                    scroll.reflectScrolledClipView(clip)
                    afterDisplay {
                        let ms = (CACurrentMediaTime() - t0) * 1000
                        scrollSteps.append(ms)
                    }
                    await sleep(ms: 16)
                }
                await sleep(ms: 100)
                let sorted = scrollSteps.sorted()
                if !sorted.isEmpty {
                    log(String(format: "scroll n=%d p50=%.1f p95=%.1f max=%.1f over16=%d railUpdates=%d railOffset=%.0f railContent=%.0f",
                               sorted.count, sorted[sorted.count / 2],
                               sorted[min(sorted.count - 1, Int(Double(sorted.count) * 0.95))],
                               sorted.last ?? 0, sorted.filter { $0 > 16 }.count,
                               DTNativeScrollProbeStats.updates,
                               Double(DTNativeScrollProbeStats.lastOffset),
                               Double(DTNativeScrollProbeStats.lastContent)))
                }
                scrollSteps = []
            }
            done()
        }
    }

    private static var scrollSteps: [Double] = []

    private static func postKey(_ code: UInt16, window: NSWindow?) {
        if let event = NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: window?.windowNumber ?? 0, context: nil,
            characters: "\u{8}", charactersIgnoringModifiers: "\u{8}", isARepeat: false, keyCode: code
        ) {
            NSApp.postEvent(event, atStart: false)
        }
    }

    private static func findScrollView(in view: NSView) -> NSScrollView? {
        if let scroll = view as? NSScrollView { return scroll }
        for sub in view.subviews {
            if let hit = findScrollView(in: sub) { return hit }
        }
        return nil
    }

    // MARK: - Clipboard ingest (watcher capture on a private board)

    /// Times `ClipboardWatcher.capture` for a Retina-screenshot-sized PNG and a long
    /// text, against a throwaway store. The main thread is blocked for exactly this long.
    private static func runClipIngest(_ runs: Int) async {
        await sleep(ms: 2000)
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("dtperf-ingest-\(getpid())")
        let store = ClipboardHistoryStore(folder: root)
        store.historyLimitOverride = 200
        let watcher = ClipboardWatcher(store: store)
        let board = NSPasteboard(name: NSPasteboard.Name("com.bicrick.PromptAnnotator.perf.ingest"))
        for run in 1...runs {
            let png = syntheticPNG(width: 3456, height: 2234, seed: run)
            board.clearContents()
            board.setData(png, forType: .png)
            let t0 = CACurrentMediaTime()
            watcher.capture(from: board)
            let imageMs = (CACurrentMediaTime() - t0) * 1000
            board.clearContents()
            board.setString(String(repeating: "lorem ipsum dolor \(run) ", count: 4000), forType: .string)
            let t1 = CACurrentMediaTime()
            watcher.capture(from: board)
            let textMs = (CACurrentMediaTime() - t1) * 1000
            log(String(format: "ingest run=%d imagePNG=%.0fKB image=%.1f text=%.1f items=%d",
                       run, Double(png.count) / 1024, imageMs, textMs, store.items.count))
            await sleep(ms: 300)
        }
        board.releaseGlobally()
        try? FileManager.default.removeItem(at: root)
        quitIfRequested()
    }

    /// Screenshot-like content: flat panels, text and some noise, so PNG size is realistic.
    static func syntheticPNG(width: Int, height: Int, seed: Int) -> Data {
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height, bitsPerSample: 8,
            samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
            bytesPerRow: 0, bitsPerPixel: 0
        ), let context = NSGraphicsContext(bitmapImageRep: rep) else { return Data() }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        NSColor(calibratedWhite: 0.96, alpha: 1).setFill()
        NSRect(x: 0, y: 0, width: width, height: height).fill()
        var rng = UInt64(truncatingIfNeeded: seed) &* 0x9E3779B97F4A7C15 | 1
        func next() -> Double {
            rng ^= rng << 13; rng ^= rng >> 7; rng ^= rng << 17
            return Double(rng % 10_000) / 10_000
        }
        for _ in 0..<60 {
            NSColor(calibratedHue: next(), saturation: 0.3, brightness: 0.9, alpha: 1).setFill()
            NSRect(x: next() * Double(width), y: next() * Double(height),
                   width: 200 + next() * 900, height: 60 + next() * 500).fill()
        }
        let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 26), .foregroundColor: NSColor.black]
        var y = 40.0
        while y < Double(height) - 40 {
            ("func render() { let value = \(Int(next() * 99999)) // session \(seed) " + String(repeating: "abc ", count: Int(next() * 30)))
                .draw(at: NSPoint(x: 60 + next() * 200, y: y), withAttributes: attrs)
            y += 38
        }
        NSGraphicsContext.restoreGraphicsState()
        return rep.representation(using: .png, properties: [:]) ?? Data()
    }

    // MARK: - Clipboard seeding

    private static func seedClipboardIfRequested() {
        let count = args.integer(forKey: "DTPerfSeedClipboard")
        guard count > 0, clipboardRootOverride != nil else { return }
        let store = ClipboardHistoryStore.shared
        guard store.items.count < count else { return }
        store.perfSeed(count: count)
        log("seeded clipboard \(store.items.count)")
    }
}
