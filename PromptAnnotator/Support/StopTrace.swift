import Foundation
import os
import QuartzCore

/// Always-on stop → paste latency trace. One interval per stop, from the hotkey event
/// (or push-to-talk key-up) to the synthetic ⌘V. Cheap: a handful of timestamps.
///
/// - Instruments: os_signpost interval "stop" (subsystem com.bicrick.PromptAnnotator,
///   category StopLatency) with an event per phase.
/// - Unified log: one `stop …` summary line per stop, numbers only, no transcript text.
///   `log show --predicate 'subsystem == "com.bicrick.PromptAnnotator" AND category == "StopLatency"'`
/// - `recent` keeps the last 50 summaries for Export diagnostics.
@MainActor
enum StopTrace {
    static let signposter = OSSignposter(subsystem: "com.bicrick.PromptAnnotator", category: "StopLatency")
    private static let logger = Logger(subsystem: "com.bicrick.PromptAnnotator", category: "StopLatency")

    private struct Open {
        var origin: CFTimeInterval
        var triggerLag: Double
        var state: OSSignpostIntervalState
        var marks: [(String, Double)] = []
        var notes: [String] = []
    }

    private static var open: Open?
    /// Uptime (ProcessInfo.systemUptime base) of the last stop-key event.
    private static var pendingTrigger: TimeInterval?
    private(set) static var recent: [String] = []
    /// Summary of the last closed trace, for the harness.
    private(set) static var lastSummary: String?
    /// ms from origin to the ⌘V post of the last closed trace (nil when nothing was pasted).
    private(set) static var lastPasteMs: Double?

    /// Remembers when the stop key was pressed or released (event timestamp, systemUptime base).
    static func noteTrigger(uptime: TimeInterval) {
        pendingTrigger = uptime
    }

    /// Opens the trace at the top of `finish()`. Uses the pending key event as origin when fresh.
    static func begin() {
        if open != nil { end("superseded") }
        let now = CACurrentMediaTime()
        var lag = 0.0
        if let trigger = pendingTrigger {
            let age = ProcessInfo.processInfo.systemUptime - trigger
            if age >= 0, age < 2 { lag = age }
        }
        pendingTrigger = nil
        let state = signposter.beginInterval("stop", id: signposter.makeSignpostID())
        open = Open(origin: now - lag, triggerLag: lag * 1000, state: state)
        lastPasteMs = nil
    }

    static var isOpen: Bool { open != nil }

    /// Marks a phase boundary (ms since the key event).
    static func mark(_ label: String) {
        PerfSuite.stopMark(label)
        guard var trace = open else { return }
        let ms = (CACurrentMediaTime() - trace.origin) * 1000
        trace.marks.append((label, ms))
        open = trace
        signposter.emitEvent("phase", "\(label, privacy: .public)")
    }

    /// Free-form key=value context (numbers / enums only, never transcript text).
    static func note(_ key: String, _ value: String) {
        guard var trace = open else { return }
        trace.notes.append("\(key)=\(value)")
        open = trace
    }

    /// Closes the trace. `outcome` is paste, hold, skip, empty, error or superseded.
    static func end(_ outcome: String) {
        guard let trace = open else { return }
        open = nil
        let total = (CACurrentMediaTime() - trace.origin) * 1000
        signposter.endInterval("stop", trace.state, "\(outcome, privacy: .public)")
        if outcome == "paste", let posted = trace.marks.last(where: { $0.0 == "pastePosted" }) {
            lastPasteMs = posted.1
        }
        var parts = [String(format: "outcome=%@ total=%.0f key=%.0f", outcome, total, trace.triggerLag)]
        parts += trace.marks.map { String(format: "%@=%.0f", $0.0, $0.1) }
        parts += trace.notes
        let summary = parts.joined(separator: " ")
        lastSummary = summary
        logger.notice("stop \(summary, privacy: .public)")
        recent.append("\(Stamp.iso.string(from: Date())) \(summary)")
        if recent.count > 50 { recent.removeFirst(recent.count - 50) }
    }
}
