import AppKit
import ApplicationServices
import os

enum SessionPhase: Equatable {
    case idle
    case recording
    case finishing
    case downloading(Double)
    case preparingModel
    case transcribing
}

private struct StoredGroup {
    var index: Int
    var committedAt: TimeInterval
    var display: DisplaySnapshot
    var shapes: [AnnotationShape]
    var image: CGImage
    var frameURL: URL
    var isClean: Bool
    /// The full-frame shot saved at Stop when the session has no other tiles.
    var isFallbackFrame: Bool
}

@MainActor
final class SessionController: ObservableObject {
    static let shared = SessionController()

    @Published private(set) var phase: SessionPhase = .idle
    @Published private(set) var markupMode: MarkupMode = .capture
    @Published private(set) var showsToolbar = false
    @Published private(set) var tool: AnnotationTool = .pen
    @Published private(set) var color: InkColor = .red
    @Published private(set) var elapsed: TimeInterval = 0
    let waveform = WaveformDisplay()
    let islandChrome = IslandChromeMotion()
    @Published private(set) var captureCount = 0
    @Published private(set) var showsPenState = false
    @Published private(set) var canUndo = false
    @Published private(set) var canRedo = false
    @Published private(set) var transcriptionError: String?
    @Published private(set) var lastError: String?
    @Published private(set) var lastSessionURL: URL?
    /// Shown in the menu when session output is staged but auto-paste was held.
    @Published private(set) var pasteReadyHint: String?

    private let log = Logger(subsystem: "com.bicrick.PromptAnnotator", category: "session")
    private let chrome = ChromeHost()
    private let overlay = OverlayController()
    private let monitor = ShiftPenMonitor()
    private let audio = AudioRecorder()
    private let transcriber: any Transcribing

    private var shapes: [AnnotationShape] = []
    private var redoShapes: [AnnotationShape] = []
    private var draft: AnnotationShape?
    private var textEdit: TextEdit?
    private var textAnchor: CGPoint?
    private var drawingDisplayID: CGDirectDisplayID?
    private var selectionRect: CGRect?
    private var groups: [StoredGroup] = []
    private var redoGroups: [StoredGroup] = []
    private var caretOn = true
    private var caretTick = 0
    private var startedAt = Date()
    private var directory: URL?
    private var audioURL: URL?
    private var pasteText = ""
    private var sheetURL: URL?
    private var timer: Timer?
    private var levelsTimer: Timer?
    private var lastLevelTime: CFTimeInterval = 0
    private var motionTimer: Timer?
    private var processingOrigin: [CGFloat] = []
    private var processingStartedAt: CFTimeInterval = 0
    private var captureTail: Task<Void, Never> = Task {}
    private var isStarting = false
    private var chromeScreenID: CGDirectDisplayID?
    private var lastToggle = Date.distantPast
    private var lastOfferedPermissions: String?
    private var keepTranscribing = false
    private var speechTask: Task<Void, Never>?
    private var lastSpeechCount = 0
    private var silenceWatch = SilenceWatch()
    private var stopQueued = false
    private var clockSpan: CGFloat = 0
    /// Push-to-talk key-up arrived while `begin()` was still awaiting permissions / setup.
    private var pushToTalkReleasedWhileStarting = false
    /// Onboarding practice skips paste-on-stop so the welcome window is not disrupted.
    private var skipNextPaste = false
    /// Injectable for tests; production uses the live Accessibility probe.
    var focusProbe: any FocusedEditableProbing = SystemFocusedEditableProbe()

    var isBusy: Bool {
        switch phase {
        case .finishing, .downloading, .preparingModel, .transcribing:
            return true
        case .idle, .recording:
            return false
        }
    }

    var toggleTitle: String {
        phase == .recording ? "Stop Session" : "Start Session"
    }

    /// Menu bar glyph. Busy phases must not look idle — launch demos stop on the icon.
    var menuIcon: String {
        switch phase {
        case .recording:
            return "record.circle.fill"
        case .finishing, .downloading, .preparingModel, .transcribing:
            return "ellipsis.circle"
        case .idle:
            return "pencil.tip.crop.circle"
        }
    }

    var menuAccessibilityLabel: String {
        switch phase {
        case .recording:
            return "da transcribuh, recording"
        case .finishing:
            return "da transcribuh, saving"
        case .downloading:
            return "da transcribuh, downloading model"
        case .preparingModel:
            return "da transcribuh, preparing model"
        case .transcribing:
            return "da transcribuh, transcribing"
        case .idle:
            if let lastError, !lastError.isEmpty {
                return "da transcribuh, \(lastError)"
            }
            return "da transcribuh"
        }
    }

    var statusText: String {
        switch phase {
        case .recording:
            return "Recording"
        case .finishing:
            return "Saving"
        case .downloading(let fraction):
            guard fraction >= 0.01 else { return "Downloading model" }
            return "Downloading model \(Int((fraction * 100).rounded()))%"
        case .preparingModel:
            return "Preparing model"
        case .transcribing:
            return "Transcribing"
        case .idle:
            return ""
        }
    }

    /// Menu / home status line: live phase, else paste-ready hint, else last calm cue or error.
    var menuStatusLine: String? {
        let live = statusText
        if !live.isEmpty { return live }
        if let pasteReadyHint, !pasteReadyHint.isEmpty { return pasteReadyHint }
        if let lastError, !lastError.isEmpty { return lastError }
        return nil
    }

    init(transcriber: any Transcribing = RoutingTranscriber()) {
        self.transcriber = transcriber
        monitor.session = self
        chrome.attach(self)
        islandChrome.onFrame = { [weak self] in
            self?.placeIsland(animated: false)
        }
        overlay.onScreensChanged = { [weak self] in
            self?.syncOverlay()
        }
        let settings = AppSettings.shared
        tool = settings.defaultTool
        color = settings.defaultColor
        settings.onChromeChange = { [weak self] in
            DispatchQueue.main.async {
                self?.refreshChrome()
            }
        }
        settings.onSpeechSelectionChange = { [weak self] in
            DispatchQueue.main.async {
                self?.reloadSpeechEngine()
            }
        }
        PasteFollowUp.shared.onAwaitingPasteChange = { [weak self] awaiting in
            if !awaiting {
                self?.pasteReadyHint = nil
            }
        }
    }

    /// Unloads and re-prepares after the user switches engine or model in Settings.
    private func reloadSpeechEngine() {
        Task {
            if let router = transcriber as? RoutingTranscriber {
                await router.reloadSelection()
            } else {
                await transcriber.prepare()
            }
        }
    }

    nonisolated func toggle() {
        Task { @MainActor in
            await self.performToggle()
        }
    }

    func handleHotkey() {
        if AppSettings.shared.pushToTalk {
            if phase == .recording {
                PushToTalk.shared.disarm()
                Task { await finish() }
            } else if !isBusy {
                pushToTalkReleasedWhileStarting = false
                PushToTalk.shared.arm(keyCode: UInt16(AppSettings.shared.chord.keyCode))
                Task { await begin() }
            }
        } else {
            Task { await performToggle() }
        }
    }

    func releasePushToTalk() {
        guard AppSettings.shared.pushToTalk else { return }
        if phase == .recording {
            Task { await finish() }
        } else {
            // Key-up before or during begin (including the gap after arm before isStarting).
            // Only reached when PushToTalk was armed — menu/Home Start never arms.
            pushToTalkReleasedWhileStarting = true
        }
    }

    /// Starts a short first-run take from onboarding without pasting into the welcome window.
    /// Returns `true` when recording actually began.
    @discardableResult
    func startOnboardingPractice() async -> Bool {
        guard !isBusy, phase != .recording, !isStarting else { return false }
        skipNextPaste = true
        // Practice does not arm PTT — clear any stale release latch so begin is not auto-stopped.
        pushToTalkReleasedWhileStarting = false
        await begin()
        if phase == .recording { return true }
        skipNextPaste = false
        return false
    }

    func cancel() {
        guard phase == .recording else { return }
        PushToTalk.shared.disarm()
        pushToTalkReleasedWhileStarting = false
        skipNextPaste = false
        keepTranscribing = false
        speechTask?.cancel()
        speechTask = nil
        captureTail.cancel()
        captureTail = Task {}
        monitor.stop()
        audio.stop()
        AudioInputs.endSession()
        stopTimer()
        stopProcessingMotion()
        AppSounds.sessionStopped(heardSpeech: false)
        if let directory {
            try? FileManager.default.removeItem(at: directory)
        }
        directory = nil
        audioURL = nil
        groups = []
        captureCount = 0
        shapes = []
        draft = nil
        textEdit = nil
        stopQueued = false
        // Cancel discards the take — no clipboard staging and no paste-ready hint.
        pasteReadyHint = nil
        PasteFollowUp.shared.clearAwaitingPaste()
        setPhase(.idle)
    }

    func selectCapture() {
        guard phase == .recording || phase == .idle else { return }
        let shiftHeld = phase == .recording && monitor.shiftIsDown
        // Shift is still down: arm the snippet tool and leave the open marks on screen.
        // Committing here used to dismiss the bar and throw away the drag that followed.
        if !shiftHeld {
            let hadMarks = textEdit != nil || draft != nil || shapes.contains(where: { $0.isSignificant() })
            if phase == .recording, hadMarks {
                if textEdit != nil {
                    submitText()
                } else {
                    commitCanvas()
                }
            }
        }
        markupMode = .capture
        selectionRect = nil
        monitor.cancelHold()
        if shiftHeld {
            showsPenState = true
            setToolbarVisible(true)
            NSCursor.crosshair.set()
        } else {
            showsPenState = false
            setToolbarVisible(false)
            NSCursor.arrow.set()
        }
        syncOverlay()
        refreshControls()
    }

    func select(tool: AnnotationTool) {
        self.tool = tool
        AppSettings.shared.setDefaultTool(tool)
        if phase == .recording, monitor.shiftIsDown, textEdit == nil {
            markupMode = .annotate
            showsPenState = true
            setToolbarVisible(true)
            ToolCursors.cursor(for: tool).set()
        } else if showsPenState {
            ToolCursors.cursor(for: tool).set()
        }
    }

    func select(color: InkColor) {
        self.color = color
        AppSettings.shared.setDefaultColor(color)
        if textEdit != nil {
            textEdit?.color = color
            syncOverlay()
        }
    }

    func refreshChrome() {
        switch phase {
        case .recording:
            showRecordingChrome()
        case .finishing, .downloading, .preparingModel, .transcribing:
            showProcessingChrome(from: phase)
        case .idle:
            break
        }
    }

    private func setToolbarVisible(_ visible: Bool) {
        showsToolbar = visible
        chrome.setToolbarVisible(visible)
    }

    func undo() {
        guard phase == .recording else { return }
        if draft != nil {
            draft = nil
        } else if let shape = shapes.popLast() {
            redoShapes.append(shape)
        } else if textEdit != nil {
            textEdit = nil
        } else if let group = groups.popLast() {
            try? FileManager.default.removeItem(at: group.frameURL)
            redoGroups.append(group)
        }
        syncOverlay()
        refreshControls()
    }

    func redo() {
        guard phase == .recording else { return }
        if let shape = redoShapes.popLast() {
            shapes.append(shape)
        } else if shapes.isEmpty, textEdit == nil, draft == nil, let group = redoGroups.popLast() {
            groups.append(group)
            let image = group.image
            let url = group.frameURL
            Task(priority: .utility) {
                try? await PNG.writeAsync(image, to: url)
            }
        }
        syncOverlay()
        refreshControls()
    }

    func revealSession() {
        guard let lastSessionURL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([lastSessionURL])
    }

    func prepareModel() {
        Task { await transcriber.prepare() }
    }

    private func copyToClipboard() {
        let image = sheetURL.flatMap { NSImage(contentsOf: $0) }
        var text = pasteText
        if AppSettings.shared.capitalizeTranscript, !text.isEmpty {
            text = TranscriptText.leadingCapital(text)
        }
        pasteText = text
        SessionClipboard.copy(image: image, transcript: text)
    }

    /// Puts the last session back on the clipboard after something else overwrote it.
    func copyLastAgain() {
        guard !isBusy, phase != .recording else { return }
        if PasteFollowUp.shared.restoreClipboard() { return }
        guard lastSessionURL != nil else { return }
        copyToClipboard()
    }

    var canCopyLastAgain: Bool {
        PasteFollowUp.shared.canReplay
            || (lastSessionURL != nil && (!pasteText.isEmpty || sheetURL != nil))
    }

    private func deliverIfRequested() {
        let skipping = skipNextPaste
        if skipNextPaste {
            skipNextPaste = false
        }
        let settings = AppSettings.shared
        let hasOutput = PasteFollowUp.shared.canReplay
            || !pasteText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || sheetURL != nil
        let target = focusProbe.classifyFocusedElement()
        let action = FocusPasteDecision.action(
            target: target,
            pasteOnStop: settings.pasteOnStop,
            settingsFocused: SettingsPresenter.shared.isKey,
            skipPaste: skipping,
            hasOutput: hasOutput
        )
        switch action {
        case .skip:
            pasteReadyHint = nil
            return
        case .autoPaste:
            pasteReadyHint = nil
            let sendReturn = settings.returnOnShift && NSEvent.modifierFlags.contains(.shift)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                PasteFollowUp.shared.pasteBoth()
                guard sendReturn else { return }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.85) {
                    ReturnKey.post()
                }
            }
        case .holdPending:
            // Restage as multi-rep so ⌘V keeps images + text where the target allows it.
            let image = sheetURL.flatMap { NSImage(contentsOf: $0) }
            _ = SessionClipboard.stageCombined(image: image, transcript: pasteText)
            pasteReadyHint = PasteFollowUp.readyHint
        }
    }

    private func startSpeechFollow() {
        speechTask?.cancel()
        keepTranscribing = true
        // Stays on the main actor (SessionController is @MainActor). Cancel + throwing sleep
        // so a new follow cannot resurrect after cancel/finish.
        speechTask = Task { @MainActor in
            while !Task.isCancelled {
                do {
                    try await Task.sleep(nanoseconds: 250_000_000)
                } catch {
                    return
                }
                guard keepTranscribing, !Task.isCancelled else { return }
                let count = audio.sampleCount()
                guard count >= lastSpeechCount + 16_000 else { continue }
                let buffer = audio.copySpeechBuffer()
                lastSpeechCount = buffer.absoluteCount
                await transcriber.consume(
                    samples: buffer.samples,
                    bufferStart: buffer.timeOffset,
                    absoluteEndCount: buffer.absoluteCount
                )
            }
        }
    }

    func abandonIfRecording() {
        guard phase == .recording || phase == .finishing else { return }
        PushToTalk.shared.disarm()
        pushToTalkReleasedWhileStarting = false
        skipNextPaste = false
        keepTranscribing = false
        speechTask?.cancel()
        speechTask = nil
        captureTail.cancel()
        captureTail = Task {}
        monitor.stop()
        audio.stop()
        AudioInputs.endSession()
        stopTimer()
        stopProcessingMotion()
    }

    func hitRects() -> [CGRect] {
        chrome.hitRects()
    }

    func penTool() -> AnnotationTool {
        tool
    }

    func penKeyPolicy() -> KeyPolicy {
        if textEdit != nil { return .editing }
        if markupMode == .annotate, showsPenState || draft != nil || monitor.isAnnotating {
            return .drawing
        }
        return .passThrough
    }

    func penShift(down: Bool) {
        guard phase == .recording else { return }
        let effect = ShiftAnnotation.shiftEdge(
            down: down,
            editing: textEdit != nil,
            selecting: monitor.isSwallowingMouse && !monitor.isAnnotating,
            stroking: monitor.isAnnotating
        )
        switch effect {
        case .keepEditing:
            if !down {
                showsPenState = false
                setToolbarVisible(false)
            }
        case .keepSelecting:
            break
        case .beginDrawing:
            markupMode = .annotate
            showsPenState = true
            setToolbarVisible(true)
            chromeScreenID = ScreenGeometry.screenUnderMouse().flatMap(ScreenGeometry.displayID)
        case .finishGestureOnRelease:
            showsPenState = false
            setToolbarVisible(false)
        case .endHold:
            showsPenState = false
            setToolbarVisible(false)
            commitCanvas()
            markupMode = .capture
        }
        DispatchQueue.main.async { self.chrome.relayout() }
        refreshControls()
    }

    func penMouseDown(at point: CGPoint, display: CGDirectDisplayID) {
        guard phase == .recording, textEdit == nil else { return }
        drawingDisplayID = display
        if tool == .text {
            textAnchor = point
            draft = nil
            textEdit = TextEdit(origin: point, text: "", color: color)
        } else {
            draft = AnnotationShape(id: UUID(), tool: tool, color: color, points: [point], text: nil)
        }
        syncOverlay()
        refreshControls()
    }

    func penMouseDrag(at point: CGPoint, display: CGDirectDisplayID) {
        guard phase == .recording, display == drawingDisplayID, tool != .text, var draft else { return }
        if draft.tool == .arrow || draft.tool == .rectangle {
            if draft.points.count < 2 {
                draft.points.append(point)
            } else {
                draft.points[draft.points.count - 1] = point
            }
            self.draft = draft
            syncOverlay()
            return
        }
        if let last = draft.points.last, hypot(last.x - point.x, last.y - point.y) < 0.5 {
            return
        }
        draft.points.append(point)
        self.draft = draft
        syncOverlay()
    }

    func penMouseUp(at point: CGPoint, display: CGDirectDisplayID) {
        guard phase == .recording else { return }
        if tool == .text {
            if textEdit == nil {
                textEdit = TextEdit(origin: textAnchor ?? point, text: "", color: color)
            }
            textAnchor = nil
            draft = nil
            syncOverlay()
            refreshControls()
            return
        }
        if var draft {
            if display == drawingDisplayID {
                if draft.tool == .arrow || draft.tool == .rectangle {
                    if draft.points.count < 2 {
                        draft.points.append(point)
                    } else {
                        draft.points[draft.points.count - 1] = point
                    }
                } else if draft.points.last != point {
                    draft.points.append(point)
                }
            }
            self.draft = nil
            if draft.isSignificant() {
                shapes.append(draft)
                redoShapes.removeAll()
            }
        }
        syncOverlay()
        refreshControls()
        if !showsPenState, textEdit == nil {
            commitCanvas()
            markupMode = .capture
            setToolbarVisible(false)
        }
    }

    func captureDragBegan(origin: CGPoint, current: CGPoint, display: CGDirectDisplayID) {
        guard phase == .recording, markupMode == .capture else { return }
        drawingDisplayID = display
        selectionRect = CaptureGesture.rect(from: origin, to: current)
        // Layer-only selection update — do not redraw baked marks on drag start.
        overlay.updateSelection(selectionRect, displayID: display)
    }

    func captureDragMoved(origin: CGPoint, current: CGPoint, display: CGDirectDisplayID) {
        guard phase == .recording, display == drawingDisplayID else { return }
        guard markupMode == .capture || selectionRect != nil else { return }
        let rect = CaptureGesture.rect(from: origin, to: current)
        // Coalesce no-ops (same integral box) so 120 Hz mice do not thrash layers.
        if let previous = selectionRect,
           Int(previous.minX) == Int(rect.minX),
           Int(previous.minY) == Int(rect.minY),
           Int(previous.width) == Int(rect.width),
           Int(previous.height) == Int(rect.height) {
            return
        }
        selectionRect = rect
        overlay.updateSelection(rect, displayID: display)
    }

    func captureDragEnded(origin: CGPoint, current: CGPoint, display: CGDirectDisplayID) {
        let rect = CaptureGesture.rect(from: origin, to: current)
        let displayID = drawingDisplayID
        let armed = markupMode == .capture || selectionRect != nil
        selectionRect = nil
        drawingDisplayID = nil
        overlay.updateSelection(nil, displayID: nil)
        guard phase == .recording, armed, displayID == display else { return }
        if !monitor.shiftIsDown {
            markupMode = .capture
            showsPenState = false
        }
        guard CaptureGesture.isCapturable(rect) else { return }
        AppSounds.tileCommitted()
        enqueueCapture(
            shapes: [],
            displayID: display,
            committedAt: Date().timeIntervalSince(startedAt),
            allowEmpty: true,
            crop: rect
        )
    }

    func captureDragCancelled() {
        selectionRect = nil
        drawingDisplayID = nil
        overlay.updateSelection(nil, displayID: nil)
    }

    func penKey(_ key: PenKey) {
        guard phase == .recording else { return }
        switch key {
        case .escape:
            if textEdit != nil {
                textEdit = nil
                if !monitor.shiftIsDown {
                    showsPenState = false
                    markupMode = .capture
                    setToolbarVisible(false)
                }
            } else {
                draft = nil
            }
            syncOverlay()
            refreshControls()
        case .submit:
            submitText()
        case .backspace:
            guard var edit = textEdit, !edit.text.isEmpty else { return }
            edit.text.removeLast()
            textEdit = edit
            syncOverlay()
        case .character(let text):
            guard var edit = textEdit else { return }
            let room = 180 - edit.text.count
            guard room > 0 else { return }
            edit.text.append(contentsOf: text.prefix(room))
            edit.color = color
            textEdit = edit
            syncOverlay()
        case .undo:
            undo()
        case .redo:
            redo()
        }
    }

    private func performToggle() async {
        let now = Date()
        guard now.timeIntervalSince(lastToggle) > 0.25 else { return }
        lastToggle = now
        if isBusy { return }
        if phase == .recording {
            await finish()
        } else {
            // Menu/Home Start never arms PTT — drop any stale release latch from an earlier chord.
            pushToTalkReleasedWhileStarting = false
            await begin()
        }
    }

    private func begin() async {
        guard !isStarting, phase != .recording, !isBusy else { return }
        isStarting = true
        defer { isStarting = false }

        var access = Permissions.current()
        if !access.microphone {
            access.microphone = await Permissions.requestMicrophone()
        }
        guard access.isReady else {
            PushToTalk.shared.disarm()
            pushToTalkReleasedWhileStarting = false
            skipNextPaste = false
            offerPermissions(access)
            return
        }
        guard monitor.install() else {
            PushToTalk.shared.disarm()
            pushToTalkReleasedWhileStarting = false
            skipNextPaste = false
            if !AXIsProcessTrusted() {
                offerPermissions(Permissions.Status(accessibility: false, microphone: true, screen: true))
            } else {
                lastError = "Couldn't watch the pointer."
                presentError("Couldn't watch the pointer", "Accessibility is on, but the event tap did not install. Quit and reopen da transcribuh.")
            }
            return
        }

        do {
            let folder = try SessionPaths.makeSessionDirectory(at: Date())
            let audioFile = folder.appendingPathComponent("audio.m4a")
            startedAt = Date()
            let preferences = AppSettings.shared
            AudioInputs.beginSession(uid: preferences.inputDeviceUID, raiseVolume: preferences.raiseInputVolume)
            try audio.start(url: audioFile)
            directory = folder
            audioURL = audioFile
            resetCanvas()
            groups = []
            captureCount = 0
            redoGroups = []
            pasteText = ""
            sheetURL = nil
            transcriptionError = nil
            lastError = nil
            pasteReadyHint = nil
            PasteFollowUp.shared.clearAwaitingPaste()
            lastSpeechCount = 0
            silenceWatch = SilenceWatch()
            stopQueued = false
            elapsed = 0
            waveform.set(FrequencyBands.resting(WaveformSamples.count))
            showsPenState = false
            markupMode = .capture
            showsToolbar = false
            selectionRect = nil
            tool = AppSettings.shared.defaultTool
            color = AppSettings.shared.defaultColor
            lastOfferedPermissions = nil
            setPhase(.recording)
            startTimer()
            transcriber.resetLive()
            startSpeechFollow()
            prepareModel()
            // Warm ScreenCaptureKit window list once per session; refresh on display change.
            ShareableContentCacheWatcher.installIfNeeded()
            Task(priority: .utility) {
                _ = try? await ShareableContentCache.shared.content(forceRefresh: true)
            }
            AppSounds.sessionStarted()
            log.info("Session started at \(folder.path, privacy: .public)")

            // Push-to-talk release during permission wait would otherwise leave the session running.
            // Only the latch — never `!isArmed`, which would auto-stop menu/Home Start (they never arm).
            let stopForPushToTalk = preferences.pushToTalk && pushToTalkReleasedWhileStarting
            pushToTalkReleasedWhileStarting = false
            if stopForPushToTalk {
                PushToTalk.shared.disarm()
                Task { await self.finish() }
            }
        } catch {
            PushToTalk.shared.disarm()
            pushToTalkReleasedWhileStarting = false
            skipNextPaste = false
            monitor.stop()
            audio.stop()
            AudioInputs.endSession()
            if let directory {
                try? FileManager.default.removeItem(at: directory)
            }
            directory = nil
            let message = UserFacingError.sessionStart(error)
            lastError = message
            presentError("Couldn't start the session", message)
            setPhase(.idle)
        }
    }

    private func finish() async {
        guard phase == .recording else { return }
        PushToTalk.shared.disarm()
        pushToTalkReleasedWhileStarting = false
        let heardSpeech = audio.heardSpeech()
        AppSounds.sessionStopped(heardSpeech: heardSpeech)
        setPhase(.finishing)
        startProcessingMotion()
        defer {
            stopProcessingMotion()
            stopQueued = false
        }
        monitor.stop()
        showsPenState = false
        selectionRect = nil
        NSCursor.arrow.set()
        stopTimer()

        if let textEdit {
            let trimmed = textEdit.text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                var edit = textEdit
                edit.text = trimmed
                shapes.append(edit.shape())
            }
            self.textEdit = nil
        }
        bakeDraft()
        if shapes.contains(where: { $0.isSignificant() }) {
            let committed = shapes.filter { $0.isSignificant() }
            let displayID = drawingDisplayID
            let at = Date().timeIntervalSince(startedAt)
            shapes = []
            draft = nil
            enqueueCapture(shapes: committed, displayID: displayID, committedAt: at, allowEmpty: false)
        } else {
            shapes = []
            draft = nil
        }
        syncOverlay()

        await captureTail.value
        if groups.isEmpty {
            let pending = shapes.filter { $0.isSignificant() }
            if !pending.isEmpty {
                shapes = []
                await performCapture(
                    shapes: pending,
                    displayID: drawingDisplayID,
                    committedAt: Date().timeIntervalSince(startedAt),
                    allowEmpty: false
                )
            }
        }
        keepTranscribing = false
        await speechTask?.value
        speechTask = nil
        audio.stop()
        AudioInputs.endSession()
        // When the live PCM buffer was trimmed, prefer the AAC file so the dropped prefix is not lost.
        let speechBuffer = audio.copySpeechBuffer()
        let spokenSamples: [Float]
        if speechBuffer.isComplete {
            spokenSamples = SampleNormalize.apply(
                speechBuffer.samples,
                enabled: AppSettings.shared.normalizeSpeech
            )
        } else {
            spokenSamples = []
        }
        overlay.hide()
        let ended = Date()
        guard let directory else {
            skipNextPaste = false
            lastError = "The session folder is missing."
            setPhase(.idle)
            return
        }

        var spoken: [TimedWord] = []
        var model: String?
        if heardSpeech, let audioURL {
            if AppSettings.shared.speechEngine == .openAICompatible {
                setPhase(.transcribing)
            } else if WhisperKitTranscriber.isModelReady {
                setPhase(.transcribing)
            } else if WhisperKitTranscriber.modelIsInstalled() {
                setPhase(.preparingModel)
            } else {
                setPhase(.downloading(0))
            }
            do {
                let transcript = try await transcriber.transcribe(
                    audioURL: audioURL,
                    samples: spokenSamples
                ) { progress in
                    Task { @MainActor in
                        switch progress {
                        case .downloading(let fraction):
                            self.setPhase(.downloading(fraction))
                        case .preparing:
                            self.setPhase(.preparingModel)
                        case .transcribing:
                            self.setPhase(.transcribing)
                        }
                    }
                }
                spoken = transcript.words
                model = transcript.model
            } catch {
                let message = UserFacingError.transcription(error)
                transcriptionError = message
                lastError = message
                ErrorLog.record("Transcription failed: \(error.localizedDescription)")
                log.error("Transcription failed: \(error.localizedDescription, privacy: .public)")
            }
        }

        // Quiet stop with no tiles: drop the folder, leave History/stats/clipboard alone.
        if SessionEmptyTake.shouldDiscard(
            words: spoken,
            tileCount: groups.count,
            transcriptionError: transcriptionError
        ) {
            discardEmptyTake(directory: directory)
            return
        }

        do {
            let exportGroups = groups.map {
                ExportGroup(
                    index: $0.index,
                    committedAt: $0.committedAt,
                    display: $0.display,
                    shapes: $0.shapes,
                    image: $0.image
                )
            }
            // Markdown/JSON + contact-sheet thumbnail off MainActor.
            let saved = try await SessionWriter.writeAsync(
                directory: directory,
                started: startedAt,
                ended: ended,
                groups: exportGroups,
                words: spoken,
                model: model,
                transcriptionError: transcriptionError
            )
            pasteText = saved.pasteText
            sheetURL = saved.sheetURL
            lastSessionURL = directory
            // Empty clipboard text after silence looks like a broken stop — surface a calm cue.
            // Prefer an existing transcription failure message when both apply.
            // (Image-only takes still land here; pure quiet takes were discarded above.)
            if saved.pasteText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
               transcriptionError == nil {
                lastError = "No speech detected"
            }
            copyToClipboard()
            deliverIfRequested()
            NotificationCenter.default.post(name: .promptAnnotatorSessionsChanged, object: nil)
            setPhase(.idle)
        } catch {
            skipNextPaste = false
            let message = UserFacingError.sessionWrite(error)
            lastError = message
            ErrorLog.record("Couldn't write the session: \(error.localizedDescription)")
            presentError("Couldn't write the session", message)
            lastSessionURL = directory
            setPhase(.idle)
        }
    }

    /// Silent island dismiss for empty+no-tiles takes: no History write, no pasteboard touch.
    private func discardEmptyTake(directory: URL) {
        skipNextPaste = false
        try? FileManager.default.removeItem(at: directory)
        self.directory = nil
        audioURL = nil
        groups = []
        captureCount = 0
        pasteText = ""
        sheetURL = nil
        // Keep the calm quiet-room cue in the menu; do not stage clipboard or paste.
        if transcriptionError == nil {
            lastError = "No speech detected"
        }
        pasteReadyHint = nil
        PasteFollowUp.shared.clearAwaitingPaste()
        setPhase(.idle)
    }

    private func commitCanvas() {
        guard textEdit == nil else { return }
        bakeDraft()
        let committed = shapes.filter { $0.isSignificant() }
        let displayID = drawingDisplayID
        let at = Date().timeIntervalSince(startedAt)
        shapes = []
        draft = nil
        redoShapes = []
        syncOverlay()
        refreshControls()
        guard !committed.isEmpty else { return }
        AppSounds.tileCommitted()
        enqueueCapture(shapes: committed, displayID: displayID, committedAt: at, allowEmpty: false)
    }

    private func bakeDraft() {
        if let draft, draft.isSignificant() {
            shapes.append(draft)
            redoShapes.removeAll()
        }
        draft = nil
    }

    private func submitText() {
        let trimmed = textEdit?.text.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if var edit = textEdit, !trimmed.isEmpty {
            edit.text = trimmed
            edit.color = color
            shapes.append(edit.shape())
            redoShapes.removeAll()
        }
        textEdit = nil
        if !monitor.shiftIsDown {
            showsPenState = false
            markupMode = .capture
            setToolbarVisible(false)
        }
        syncOverlay()
        commitCanvas()
    }

    private func enqueueCapture(
        shapes: [AnnotationShape],
        displayID: CGDirectDisplayID?,
        committedAt: TimeInterval,
        allowEmpty: Bool,
        crop: CGRect? = nil,
        fallbackFrame: Bool = false
    ) {
        let previous = captureTail
        // Serial chain stays on MainActor for session state; capture+encode hop off inside.
        captureTail = Task { @MainActor in
            await previous.value
            await self.performCapture(
                shapes: shapes,
                displayID: displayID,
                committedAt: committedAt,
                allowEmpty: allowEmpty,
                crop: crop,
                fallbackFrame: fallbackFrame
            )
        }
    }

    private func performCapture(
        shapes: [AnnotationShape],
        displayID: CGDirectDisplayID?,
        committedAt: TimeInterval,
        allowEmpty: Bool,
        crop: CGRect? = nil,
        fallbackFrame: Bool = false
    ) async {
        let significant = shapes.filter { $0.isSignificant() }
        if significant.isEmpty, !allowEmpty { return }
        guard let directory else { return }
        guard !Task.isCancelled else { return }

        let screen: NSScreen?
        if let displayID {
            screen = ScreenGeometry.screen(for: displayID)
        } else {
            screen = ScreenGeometry.screenUnderMouse()
        }
        guard let screen, let resolvedID = ScreenGeometry.displayID(of: screen) else {
            lastError = "Couldn't find the display to capture."
            restore(significant, allowEmpty: allowEmpty)
            return
        }

        // Hold the session folder across the await. Cancel clears `directory`; a new
        // session replaces it. Either way, discard this shot instead of writing again.
        let sessionDirectory = directory
        let excludedWindowIDs = overlay.windowIDs() + chrome.windowIDs()
        let pointSize = screen.frame.size
        let index = groups.count + 1
        let url = sessionDirectory.appendingPathComponent(String(format: "frames/%02d.png", index))
        // Snapshot screen metrics for DisplaySnapshot after the off-main hop.
        let screenForSnapshot = screen

        do {
            // Detached so PNG/ImageIO never resume onto MainActor.
            // userInitiated: above utility encode, below audio real-time.
            let image = try await Task.detached(priority: .userInitiated) {
                try await CapturePipeline.captureAndEncode(
                    displayID: resolvedID,
                    pointSize: pointSize,
                    shapes: significant,
                    excludedWindowIDs: excludedWindowIDs,
                    crop: crop,
                    url: url
                )
            }.value
            guard !Task.isCancelled, self.directory == sessionDirectory else { return }
            let ui = CapturePerf.begin(.uiUpdate)
            groups.append(
                StoredGroup(
                    index: index,
                    committedAt: committedAt,
                    display: DisplaySnapshot(
                        screen: screenForSnapshot,
                        pixelWidth: image.width,
                        pixelHeight: image.height,
                        contentSize: crop?.standardized.size
                    ),
                    shapes: significant,
                    image: image,
                    frameURL: url,
                    isClean: significant.isEmpty,
                    isFallbackFrame: fallbackFrame && crop == nil
                )
            )
            redoGroups.removeAll()
            refreshControls()
            CapturePerf.end(.uiUpdate, ui)
        } catch {
            guard self.directory == sessionDirectory else { return }
            if let export = error as? ExportError, export.message.contains("too small") {
                lastError = "The selection was too small to capture."
                return
            }
            log.error("Capture failed: \(error.localizedDescription, privacy: .public)")
            lastError = UserFacingError.capture(error)
            restore(significant, allowEmpty: allowEmpty)
        }
    }

    private func restore(_ shapes: [AnnotationShape], allowEmpty: Bool) {
        guard !allowEmpty, !shapes.isEmpty, self.shapes.isEmpty, draft == nil, textEdit == nil else { return }
        self.shapes = shapes
        syncOverlay()
        refreshControls()
    }

    private func resetCanvas() {
        shapes = []
        redoShapes = []
        draft = nil
        textEdit = nil
        textAnchor = nil
        drawingDisplayID = nil
        selectionRect = nil
        caretOn = true
        syncOverlay()
        refreshControls()
    }

    private func syncOverlay() {
        overlay.update(
            shapes: shapes,
            draft: draft,
            textEdit: textEdit,
            caretOn: caretOn,
            selection: selectionRect,
            displayID: drawingDisplayID
        )
    }

    private func refreshControls() {
        canUndo = draft != nil || !shapes.isEmpty || textEdit != nil || !groups.isEmpty
        canRedo = !redoShapes.isEmpty || (textEdit == nil && draft == nil && shapes.isEmpty && !redoGroups.isEmpty)
        let count = groups.count
        let countChanged = count != captureCount
        captureCount = count
        if countChanged, phase == .recording {
            let animate = !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
            islandChrome.setTargets(
                IslandSlots.recording(style: AppSettings.shared.islandStyle, captures: count),
                animated: animate
            )
        }
    }

    private func setPhase(_ phase: SessionPhase) {
        let previous = self.phase
        self.phase = phase
        switch phase {
        case .recording:
            overlay.show()
            showRecordingChrome()
        case .finishing, .downloading, .preparingModel, .transcribing:
            overlay.hide()
            showProcessingChrome(from: previous)
        case .idle:
            overlay.hide()
            hideChrome()
        }
    }

    /// NSPanel frame including the double-pane gutter (`Ink.buttonShadow`).
    func islandPanelSize() -> CGSize {
        IslandMetrics.layout(
            style: AppSettings.shared.islandStyle,
            slots: islandChrome.slots,
            captures: captureCount,
            elapsed: elapsed
        ).chrome
    }

    /// Face size only — used to keep the bar visually centered (shadow hangs down-right).
    func islandBarSize() -> CGSize {
        IslandMetrics.layout(
            style: AppSettings.shared.islandStyle,
            slots: islandChrome.slots,
            captures: captureCount,
            elapsed: elapsed
        ).panel
    }

    private func placeIsland(animated: Bool) {
        guard islandChrome.presence != .hidden else { return }
        chrome.placeIsland(islandPanelSize(), animated: animated && !islandChrome.isAnimating)
    }

    private func showRecordingChrome() {
        let style = AppSettings.shared.islandStyle
        if style == .hidden {
            let shown = islandChrome.presence != .hidden
            islandChrome.freeze()
            chrome.dismissIsland(animated: shown, hideToolbar: false) { [weak self] in
                self?.islandChrome.setPresence(.hidden)
                self?.islandChrome.snap(.closed)
            }
            return
        }
        let fade = islandChrome.presence == .hidden
        if fade {
            chrome.beginIslandReveal()
        }
        islandChrome.setPresence(.recording)
        let animateSlots = !fade && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        islandChrome.setTargets(
            IslandSlots.recording(style: style, captures: captureCount),
            animated: animateSlots
        )
        chrome.revealIsland(size: islandPanelSize(), fadeIn: fade)
        if showsToolbar {
            chrome.setToolbarVisible(true)
        }
    }

    private func showProcessingChrome(from previous: SessionPhase) {
        let wasHidden = islandChrome.presence == .hidden
        let entering = wasHidden || !Self.phaseIsBusy(previous)
        if wasHidden {
            chrome.beginIslandReveal()
        }
        islandChrome.setPresence(.processing)
        islandChrome.setTargets(IslandSlots.processing(phase: phase), animated: !wasHidden)
        showsToolbar = false
        chrome.hideToolbar()
        if entering || wasHidden {
            chrome.revealIsland(size: islandPanelSize(), fadeIn: wasHidden)
        } else if !islandChrome.isAnimating {
            placeIsland(animated: false)
        }
    }

    private func hideChrome() {
        islandChrome.freeze()
        showsToolbar = false
        chrome.dismissIsland(animated: islandChrome.presence != .hidden, hideToolbar: true) { [weak self] in
            self?.islandChrome.setPresence(.hidden)
            self?.islandChrome.snap(.closed)
        }
    }

    private static func phaseIsBusy(_ phase: SessionPhase) -> Bool {
        switch phase {
        case .finishing, .downloading, .preparingModel, .transcribing:
            return true
        case .idle, .recording:
            return false
        }
    }

    private func startProcessingMotion() {
        motionTimer?.invalidate()
        processingOrigin = waveform.levels
        processingStartedAt = CACurrentMediaTime()
        let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.advanceProcessingMotion()
            }
        }
        timer.tolerance = 1.0 / 240.0
        motionTimer = timer
        RunLoop.main.add(timer, forMode: .common)
        advanceProcessingMotion()
    }

    private func advanceProcessingMotion() {
        guard isBusy else { return }
        let elapsed = CACurrentMediaTime() - processingStartedAt
        let wave = WaveformMotion.loading(time: elapsed)
        let from = processingOrigin.isEmpty ? wave : processingOrigin
        waveform.set(WaveformMotion.mix(from, wave, amount: WaveformMotion.blend(elapsed)))
    }

    private func stopProcessingMotion() {
        motionTimer?.invalidate()
        motionTimer = nil
        processingOrigin = []
    }

    private func startTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.tick()
            }
        }
        startLevelTimer()
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
        stopLevelTimer()
    }

    private func startLevelTimer() {
        levelsTimer?.invalidate()
        lastLevelTime = 0
        let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.refreshLevels()
            }
        }
        timer.tolerance = 1.0 / 240.0
        levelsTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func stopLevelTimer() {
        levelsTimer?.invalidate()
        levelsTimer = nil
        lastLevelTime = 0
    }

    private func refreshLevels() {
        guard phase == .recording else { return }
        let now = CACurrentMediaTime()
        let delta = lastLevelTime == 0 ? (1.0 / 60.0) : min(0.05, now - lastLevelTime)
        lastLevelTime = now
        waveform.set(audio.sampleLevels(delta: delta))
    }

    private func tick() {
        guard phase == .recording else { return }
        let now = Date().timeIntervalSince(startedAt)
        // The clock shows whole seconds. Publishing every 0.1 s tick
        // re-rendered every SessionController observer (island, menu bar,
        // the whole Settings window) ten times a second while recording.
        if Int(now) != Int(elapsed) || now < elapsed {
            elapsed = now
        }
        let span = IslandMetrics.clockSpan(now)
        if span != clockSpan {
            clockSpan = span
            placeIsland(animated: false)
        }
        let settings = AppSettings.shared
        let quietLongEnough = silenceWatch.tick(
            level: audio.latestLevel(),
            heardSpeech: audio.heardSpeech(),
            limit: settings.silenceStopSeconds,
            delta: 0.1
        )
        if !stopQueued, quietLongEnough || SessionLimits.reachedMax(elapsed: now, minutes: settings.maxSessionMinutes) {
            stopQueued = true
            Task { await self.finish() }
        }
        if textEdit != nil {
            caretTick += 1
            if caretTick.isMultiple(of: 5) {
                caretOn.toggle()
                syncOverlay()
            }
        }
        guard !monitor.isSwallowingMouse,
              let screen = ScreenGeometry.screenUnderMouse(),
              let id = ScreenGeometry.displayID(of: screen),
              id != chromeScreenID else {
            return
        }
        chromeScreenID = id
        chrome.relayout()
    }

    private func offerPermissions(_ status: Permissions.Status) {
        lastError = status.summary.map { "Turn on \($0), then reopen the app." }
        // Re-open Settings when the missing set changes (e.g. mic granted, screen still off).
        let missing = status.summary ?? ""
        guard missing != lastOfferedPermissions else { return }
        lastOfferedPermissions = missing
        Permissions.revealSettings(for: status)
    }

    private func presentError(_ title: String, _ message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
        ErrorLog.record("\(title): \(message)")
    }
}
