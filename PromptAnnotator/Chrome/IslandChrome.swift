import AppKit
import SwiftUI

/// How open each piece of recording chrome is. Zero is gone, one is fully in the capsule.
/// Left slot = record square + timer. Right slot = capture chip (or download %). No text label.
struct IslandSlots: Equatable {
    var label: CGFloat = 0
    var dot: CGFloat = 0
    var clock: CGFloat = 0
    var chip: CGFloat = 0
    var percent: CGFloat = 0

    static func recording(style: IslandStyle, captures: Int) -> IslandSlots {
        switch style {
        case .classic, .compact:
            return IslandSlots(
                dot: 1,
                clock: 1,
                chip: captures > 0 ? 1 : 0
            )
        case .minimal, .hidden:
            return IslandSlots()
        }
    }

    static func processing(phase: SessionPhase) -> IslandSlots {
        guard case .downloading(let fraction) = phase, fraction >= 0.01 else {
            return IslandSlots()
        }
        return IslandSlots(percent: 1)
    }

    static var closed: IslandSlots { IslandSlots() }

    func approached(toward target: IslandSlots, delta: TimeInterval, tau: TimeInterval) -> IslandSlots {
        IslandSlots(
            label: Self.step(label, target.label, delta: delta, tau: tau),
            dot: Self.step(dot, target.dot, delta: delta, tau: tau),
            clock: Self.step(clock, target.clock, delta: delta, tau: tau),
            chip: Self.step(chip, target.chip, delta: delta, tau: tau),
            percent: Self.step(percent, target.percent, delta: delta, tau: tau)
        )
    }

    func isClose(to target: IslandSlots, epsilon: CGFloat) -> Bool {
        abs(label - target.label) < epsilon
            && abs(dot - target.dot) < epsilon
            && abs(clock - target.clock) < epsilon
            && abs(chip - target.chip) < epsilon
            && abs(percent - target.percent) < epsilon
    }

    /// Fades with the travel, and finishes fading just before the slot has fully closed.
    static func opacity(for open: CGFloat) -> Double {
        let amount = min(1, max(0, Double(open)))
        return min(1, amount / 0.72)
    }

    static func step(_ value: CGFloat, _ target: CGFloat, delta: TimeInterval, tau: TimeInterval) -> CGFloat {
        guard tau > 0 else { return target }
        let rate = CGFloat(1 - exp(-max(0, delta) / tau))
        return value + (target - value) * rate
    }
}

enum IslandPresence: Equatable {
    case hidden
    case recording
    case processing
}

/// Sizes for the capsule. Left and right side slots share one fixed width so the comb stays centered.
struct IslandLayout: Equatable {
    var panel = CGSize(width: 280, height: 54)
    var side: CGFloat = 0
    var wave = CGSize(width: 248, height: 32)
    /// Gap between each side slot and the waveform (equal L/R).
    var sideGap: CGFloat = 0
    var record: CGFloat = 0
    var clock: CGFloat = 0
    var recordClockGap: CGFloat = 0
    var chip: CGFloat = 0
    var percent: CGFloat = 0
}

enum IslandMetrics {
    /// Outer padding left/right — equal.
    static let inset: CGFloat = 18
    /// Padding between each side slot and the waveform — equal.
    static let sideGap: CGFloat = 16
    /// Gap between record square and timer inside the left slot.
    static let recordClockGap: CGFloat = 8
    static let recordSize: CGFloat = 10
    static let clockFontSize: CGFloat = 14
    static let chipFontSize: CGFloat = 14
    static let chipIconSize: CGFloat = 12
    /// Fixed monospaced timer width (covers `59:59` and `9:59:59`) — no jitter as digits change.
    static let fixedClockSpan: CGFloat = {
        let m = textWidth("59:59", size: clockFontSize)
        let h = textWidth("9:59:59", size: clockFontSize)
        return max(m, h) + 2
    }()

    static func layout(
        style: IslandStyle,
        slots: IslandSlots,
        captures: Int,
        elapsed: TimeInterval
    ) -> IslandLayout {
        _ = elapsed // timer uses fixed span — elapsed no longer changes geometry
        let leadingNatural = recordSize + recordClockGap + fixedClockSpan
        let trailingNatural = max(chipSpan(max(captures, 1)), percentSpan)

        let leadingOpen = max(slots.dot, slots.clock)
        let trailingOpen = max(slots.chip, slots.percent)
        let open = max(leadingOpen, trailingOpen)

        // Side width is the max of the two natural contents, scaled by overall open amount
        // so the comb stays centered while chrome collapses to processing/hidden.
        let sideFull = max(leadingNatural, trailingNatural)
        let side = sideFull * open
        let gap = sideGap * open

        let wave = CGSize(width: waveformWidth(style), height: waveformHeight(style))
        let panel = CGSize(
            width: inset * 2 + side + gap + wave.width + gap + side,
            height: barHeight(style)
        )
        return IslandLayout(
            panel: panel,
            side: side,
            wave: wave,
            sideGap: gap,
            record: recordSize * leadingOpen,
            clock: fixedClockSpan * slots.clock,
            recordClockGap: recordClockGap * slots.clock,
            chip: chipSpan(captures) * slots.chip,
            percent: percentSpan * slots.percent
        )
    }

    static func waveformWidth(_ style: IslandStyle) -> CGFloat {
        switch style {
        case .classic:
            return 248
        case .compact:
            return 188
        case .minimal, .hidden:
            return 220
        }
    }

    static func waveformHeight(_ style: IslandStyle) -> CGFloat {
        switch style {
        case .classic, .hidden:
            return 32
        case .compact:
            return 26
        case .minimal:
            return 28
        }
    }

    static func barHeight(_ style: IslandStyle) -> CGFloat {
        switch style {
        case .classic, .hidden:
            return 54
        case .compact, .minimal:
            return 48
        }
    }

    /// Kept for SessionController tick — always fixed so the island does not reflow.
    static func clockSpan(_ elapsed: TimeInterval) -> CGFloat {
        _ = elapsed
        return fixedClockSpan
    }

    static let percentSpan: CGFloat = 44

    static func chipSpan(_ count: Int) -> CGFloat {
        let digits = textWidth("\(max(count, 1))", size: chipFontSize)
        // digit + gap + icon + horizontal pad (space2 * 2)
        return ceil(digits + 6 + chipIconSize + Ink.space2 * 2) + 2
    }

    private static func textWidth(_ text: String, size: CGFloat) -> CGFloat {
        FontMetrics.width(of: text, size: size, weight: .regular, mono: true)
    }
}

/// Eases the side pieces. The view reads `slots`; each tick asks the capsule to match.
@MainActor
final class IslandChromeMotion: ObservableObject {
    @Published private(set) var presence: IslandPresence = .hidden
    @Published private(set) var slots = IslandSlots()

    var onFrame: (() -> Void)?
    private(set) var isAnimating = false

    private var targets = IslandSlots()
    private var timer: Timer?
    private var lastTick: CFTimeInterval = 0

    func setPresence(_ presence: IslandPresence) {
        self.presence = presence
    }

    func setTargets(_ targets: IslandSlots, animated: Bool) {
        guard targets != self.targets || slots != targets else { return }
        self.targets = targets
        guard animated else {
            slots = targets
            stop()
            onFrame?()
            return
        }
        start()
    }

    func snap(_ targets: IslandSlots) {
        setTargets(targets, animated: false)
    }

    /// Stops the ease where it is so a fade-out does not also collapse the capsule.
    func freeze() {
        stop()
    }

    private func start() {
        guard timer == nil else { return }
        lastTick = 0
        let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.tick()
            }
        }
        timer.tolerance = 1.0 / 240.0
        self.timer = timer
        isAnimating = true
        RunLoop.main.add(timer, forMode: .common)
    }

    private func tick() {
        let now = CACurrentMediaTime()
        let delta = lastTick == 0 ? (1.0 / 60.0) : min(0.05, now - lastTick)
        lastTick = now
        let next = slots.approached(toward: targets, delta: delta, tau: 0.13)
        if next.isClose(to: targets, epsilon: 0.004) {
            slots = targets
            stop()
        } else {
            slots = next
        }
        onFrame?()
    }

    private func stop() {
        timer?.invalidate()
        timer = nil
        isAnimating = false
        lastTick = 0
    }
}
