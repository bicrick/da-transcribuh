import AppKit
import os

enum SessionPhase: Equatable {
    case idle
    case recording
    case finishing
    case downloading(Double)
    case preparingModel
    case transcribing
    case done
}

private struct StoredGroup {
    var index: Int
    var committedAt: TimeInterval
    var display: DisplaySnapshot
    var shapes: [AnnotationShape]
    var image: CGImage
    var frameURL: URL
    var isClean: Bool
}

@MainActor
final class SessionController: ObservableObject {
    static let shared = SessionController()

    @Published private(set) var phase: SessionPhase = .idle
    @Published private(set) var tool: AnnotationTool = .pen
    @Published private(set) var color: InkColor = .red
    @Published private(set) var elapsed: TimeInterval = 0
    @Published private(set) var levels: [CGFloat] = Array(repeating: 0.12, count: 5)
    @Published private(set) var showsPenState = false
    @Published private(set) var canUndo = false
    @Published private(set) var canRedo = false
    @Published private(set) var doneSummary = ""
    @Published private(set) var copyConfirmation: String?
    @Published private(set) var transcriptionError: String?
    @Published private(set) var hasSheet = false
    @Published private(set) var lastError: String?
    @Published private(set) var lastSessionURL: URL?

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
    private var groups: [StoredGroup] = []
    private var redoGroups: [StoredGroup] = []
    private var caretOn = true
    private var caretTick = 0
    private var startedAt = Date()
    private var directory: URL?
    private var audioURL: URL?
    private var notes = ""
    private var pasteText = ""
    private var sheetURL: URL?
    private var timer: Timer?
    private var captureTail: Task<Void, Never> = Task {}
    private var isStarting = false
    private var chromeScreenID: CGDirectDisplayID?
    private var lastToggle = Date.distantPast
    private var didOfferPermissions = false

    var isBusy: Bool {
        switch phase {
        case .finishing, .downloading, .preparingModel, .transcribing:
            return true
        case .idle, .recording, .done:
            return false
        }
    }

    var toggleTitle: String {
        phase == .recording ? "Stop Session" : "Start Session"
    }

    var menuIcon: String {
        phase == .recording ? "record.circle.fill" : "pencil.tip.crop.circle"
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
        case .idle, .done:
            return ""
        }
    }

    init(transcriber: any Transcribing = WhisperKitTranscriber()) {
        self.transcriber = transcriber
        monitor.session = self
        chrome.attach(self)
        let settings = AppSettings.shared
        tool = settings.defaultTool
        color = settings.defaultColor
        settings.onChromeChange = { [weak self] in
            self?.refreshChrome()
        }
    }

    nonisolated func toggle() {
        Task { @MainActor in
            await self.performToggle()
        }
    }

    func select(tool: AnnotationTool) {
        self.tool = tool
        AppSettings.shared.setDefaultTool(tool)
        if showsPenState {
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
            chrome.showSession()
        case .finishing, .downloading, .preparingModel, .transcribing:
            chrome.showStatus()
        case .idle, .done:
            break
        }
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
            try? PNG.write(group.image, to: group.frameURL)
            groups.append(group)
        }
        syncOverlay()
        refreshControls()
    }

    func copyToClipboard() {
        let image = sheetURL.flatMap { NSImage(contentsOf: $0) }
        let text = pasteText.isEmpty ? notes : pasteText
        guard SessionClipboard.copy(image: image, transcript: text) else { return }
        copyConfirmation = "On the clipboard"
    }

    func revealSession() {
        guard let lastSessionURL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([lastSessionURL])
    }

    func dismissDone() {
        copyConfirmation = nil
        setPhase(.idle)
    }

    func abandonIfRecording() {
        guard phase == .recording || phase == .finishing else { return }
        monitor.stop()
        audio.stop()
        timer?.invalidate()
        timer = nil
    }

    func hitRects() -> [CGRect] {
        chrome.hitRects()
    }

    func penTool() -> AnnotationTool {
        tool
    }

    func penKeyPolicy() -> KeyPolicy {
        if textEdit != nil { return .editing }
        if showsPenState || draft != nil || monitor.isSwallowingMouse { return .drawing }
        return .passThrough
    }

    func penShift(down: Bool) {
        guard phase == .recording, textEdit == nil else { return }
        showsPenState = down
        if down {
            chrome.relayout()
            chromeScreenID = ScreenGeometry.screenUnderMouse().flatMap(ScreenGeometry.displayID)
        } else if !monitor.isSwallowingMouse {
            commitCanvas()
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
        } else {
            draft = AnnotationShape(id: UUID(), tool: tool, color: color, points: [point], text: nil)
        }
        syncOverlay()
    }

    func penMouseDrag(at point: CGPoint, display: CGDirectDisplayID) {
        guard phase == .recording, display == drawingDisplayID, tool != .text, var draft else { return }
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
            textEdit = TextEdit(origin: textAnchor ?? point, text: "", color: color)
            textAnchor = nil
            draft = nil
            syncOverlay()
            refreshControls()
            return
        }
        if var draft {
            if display == drawingDisplayID, draft.points.last != point {
                draft.points.append(point)
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
        }
    }

    func penKey(_ key: PenKey) {
        guard phase == .recording else { return }
        switch key {
        case .escape:
            if textEdit != nil {
                textEdit = nil
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
            guard var edit = textEdit, edit.text.count < 180 else { return }
            edit.text.append(contentsOf: text)
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
            offerPermissions(access)
            return
        }
        guard monitor.install() else {
            if !AXIsProcessTrusted() {
                offerPermissions(Permissions.Status(accessibility: false, microphone: true, screen: true))
            } else {
                lastError = "Couldn't watch Shift."
                presentError("Couldn't watch the keyboard", "Accessibility is on, but the event tap did not install. Quit and reopen Prompt Annotator.")
            }
            return
        }

        do {
            let folder = try SessionPaths.makeSessionDirectory(at: Date())
            let audioFile = folder.appendingPathComponent("audio.m4a")
            startedAt = Date()
            try audio.start(url: audioFile)
            directory = folder
            audioURL = audioFile
            resetCanvas()
            groups = []
            redoGroups = []
            notes = ""
            pasteText = ""
            sheetURL = nil
            hasSheet = false
            transcriptionError = nil
            copyConfirmation = nil
            lastError = nil
            elapsed = 0
            showsPenState = false
            tool = AppSettings.shared.defaultTool
            color = AppSettings.shared.defaultColor
            setPhase(.recording)
            startTimer()
            AppSounds.sessionStarted()
            log.info("Session started at \(folder.path, privacy: .public)")
        } catch {
            monitor.stop()
            audio.stop()
            if let directory {
                try? FileManager.default.removeItem(at: directory)
            }
            directory = nil
            lastError = error.localizedDescription
            presentError("Couldn't start the session", error.localizedDescription)
            setPhase(.idle)
        }
    }

    private func finish() async {
        guard phase == .recording else { return }
        AppSounds.sessionStopped()
        setPhase(.finishing)
        monitor.stop()
        showsPenState = false
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
        if groups.isEmpty {
            await performCapture(
                shapes: [],
                displayID: ScreenGeometry.screenUnderMouse().flatMap(ScreenGeometry.displayID),
                committedAt: Date().timeIntervalSince(startedAt),
                allowEmpty: true
            )
        }

        audio.stop()
        overlay.hide()
        let ended = Date()
        let sessionEnd = ended.timeIntervalSince(startedAt)
        if groups.count == 1, groups[0].shapes.isEmpty {
            groups[0].committedAt = sessionEnd
        }

        guard let directory else {
            lastError = "The session folder is missing."
            setPhase(.idle)
            return
        }

        var spoken: [TimedWord] = []
        var model: String?
        if let audioURL {
            do {
                let transcript = try await transcriber.transcribe(audioURL: audioURL) { progress in
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
                transcriptionError = error.localizedDescription
                log.error("Transcription failed: \(error.localizedDescription, privacy: .public)")
            }
        }

        do {
            let saved = try SessionWriter.write(
                directory: directory,
                started: startedAt,
                ended: ended,
                groups: groups.map {
                    ExportGroup(
                        index: $0.index,
                        committedAt: $0.committedAt,
                        display: $0.display,
                        shapes: $0.shapes,
                        image: $0.image
                    )
                },
                words: spoken,
                model: model,
                transcriptionError: transcriptionError
            )
            notes = saved.notes
            pasteText = saved.pasteText
            sheetURL = saved.sheetURL
            hasSheet = saved.sheetURL != nil
            lastSessionURL = directory
            copyToClipboard()
            let tileCount = groups.count
            let noun = tileCount == 1 ? "tile" : "tiles"
            doneSummary = "\(tileCount) \(noun) · \(TimeFormat.clock(sessionEnd))"
            setPhase(.done)
        } catch {
            lastError = error.localizedDescription
            presentError("Couldn't write the session", error.localizedDescription)
            lastSessionURL = directory
            setPhase(.idle)
        }
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
        syncOverlay()
        commitCanvas()
    }

    private func enqueueCapture(
        shapes: [AnnotationShape],
        displayID: CGDirectDisplayID?,
        committedAt: TimeInterval,
        allowEmpty: Bool
    ) {
        let previous = captureTail
        captureTail = Task { @MainActor in
            await previous.value
            await self.performCapture(
                shapes: shapes,
                displayID: displayID,
                committedAt: committedAt,
                allowEmpty: allowEmpty
            )
        }
    }

    private func performCapture(
        shapes: [AnnotationShape],
        displayID: CGDirectDisplayID?,
        committedAt: TimeInterval,
        allowEmpty: Bool
    ) async {
        let significant = shapes.filter { $0.isSignificant() }
        if significant.isEmpty, !allowEmpty { return }
        guard let directory else { return }

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

        do {
            let image = try await DisplayCapture.capture(
                displayID: resolvedID,
                pointSize: screen.frame.size,
                shapes: significant,
                excludedWindowIDs: overlay.windowIDs() + chrome.windowIDs()
            )
            let index = groups.count + 1
            let url = directory.appendingPathComponent(String(format: "frames/%02d.png", index))
            try PNG.write(image, to: url)
            groups.append(
                StoredGroup(
                    index: index,
                    committedAt: committedAt,
                    display: DisplaySnapshot(screen: screen, pixelWidth: image.width, pixelHeight: image.height),
                    shapes: significant,
                    image: image,
                    frameURL: url,
                    isClean: significant.isEmpty
                )
            )
            redoGroups.removeAll()
            refreshControls()
        } catch {
            log.error("Capture failed: \(error.localizedDescription, privacy: .public)")
            lastError = error.localizedDescription
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
            displayID: drawingDisplayID
        )
    }

    private func refreshControls() {
        canUndo = draft != nil || !shapes.isEmpty || textEdit != nil || !groups.isEmpty
        canRedo = !redoShapes.isEmpty || (textEdit == nil && draft == nil && shapes.isEmpty && !redoGroups.isEmpty)
    }

    private func setPhase(_ phase: SessionPhase) {
        self.phase = phase
        switch phase {
        case .recording:
            overlay.show()
            chrome.showSession()
        case .finishing, .downloading, .preparingModel, .transcribing:
            overlay.hide()
            chrome.showStatus()
        case .done:
            overlay.hide()
            chrome.showDone()
        case .idle:
            overlay.hide()
            chrome.hideAll()
        }
        DispatchQueue.main.async { self.chrome.relayout() }
    }

    private func startTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.tick()
            }
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    private func tick() {
        guard phase == .recording else { return }
        elapsed = Date().timeIntervalSince(startedAt)
        levels = audio.sampleLevels()
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
        guard !didOfferPermissions else { return }
        didOfferPermissions = true
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
    }
}
