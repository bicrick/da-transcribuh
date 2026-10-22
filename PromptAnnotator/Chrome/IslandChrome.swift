import AppKit
import SwiftUI

/// How open each piece of recording chrome is. Zero is gone, one is fully in the capsule.
struct IslandSlots: Equatable {
    var label: CGFloat = 0
    var dot: CGFloat = 0
    var clock: CGFloat = 0
    var chip: CGFloat = 0
    var percent: CGFloat = 0

    static func recording(style: IslandStyle, captures: Int) -> IslandSlots {
        switch style {
        case .classic:
            return IslandSlots(label: 1, clock: 1, chip: captures > 0 ? 1 : 0)
        case .compact:
            return IslandSlots(dot: 1, clock: 1, chip: captures > 0 ? 1 : 0)
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

/// Sizes for the capsule. The two side slots are always the same width, so the comb
/// stays in the middle while a label or a count closes.
struct IslandLayout: Equatable {
    var panel = CGSize(width: 242, height: 46)
    var side: CGFloat = 0
    var wave = CGSize(width: 210, height: 26)
    var label: CGFloat = 0
    var dot: CGFloat = 0
    var leadingGap: CGFloat = 0
    var trailingGap: CGFloat = 0
    var clock: CGFloat = 0
    var clockChipGap: CGFloat = 0
    var chip: CGFloat = 0
    var chipPercentGap: CGFloat = 0
    var percent: CGFloat = 0
}

enum IslandMetrics {
    static let inset: CGFloat = 16

    static func layout(
        style: IslandStyle,
        slots: IslandSlots,
        captures: Int,
        elapsed: TimeInterval
    ) -> IslandLayout {
        let gap: CGFloat = style == .classic ? 14 : 12
        let label = labelSpan * slots.label
        let dot = dotSpan * slots.dot
        let leadingGap = gap * max(slots.label, slots.dot)
        let leading = label + dot + leadingGap

        let clock = clockSpan(elapsed) * slots.clock
        let chip = chipSpan(captures) * slots.chip
        let percent = percentSpan * slots.percent
        let clockChipGap = gap * min(slots.clock, slots.chip)
        let chipPercentGap = gap * min(slots.percent, max(slots.clock, slots.chip))
        let trailingGap = gap * max(slots.clock, slots.chip, slots.percent)
        let trailing = trailingGap + clock + clockChipGap + chip + chipPercentGap + percent

        let side = max(leading, trailing)
        let wave = CGSize(width: waveformWidth(style), height: waveformHeight(style))
        let panel = CGSize(
            width: inset * 2 + side + wave.width + side,
            height: barHeight(style)
        )
        return IslandLayout(
            panel: panel,
            side: side,
            wave: wave,
            label: label,
            dot: dot,
            leadingGap: leadingGap,
            trailingGap: trailingGap,
            clock: clock,
            clockChipGap: clockChipGap,
            chip: chip,
            chipPercentGap: chipPercentGap,
            percent: percent
        )
    }

    static func waveformWidth(_ style: IslandStyle) -> CGFloat {
        switch style {
        case .classic:
            return 210
        case .compact:
            return 156
        case .minimal, .hidden:
            return 196
        }
    }

    static func waveformHeight(_ style: IslandStyle) -> CGFloat {
        switch style {
        case .classic, .hidden:
            return 26
        case .compact:
            return 20
        case .minimal:
            return 22
        }
    }

    static func barHeight(_ style: IslandStyle) -> CGFloat {
        switch style {
        case .classic, .hidden:
            return 46
        case .compact, .minimal:
            return 40
        }
    }

    static func clockSpan(_ elapsed: TimeInterval) -> CGFloat {
        let text = textWidth(TimeFormat.clock(elapsed), size: 13, weight: .medium, mono: true)
        return max(44, ceil(text) + 2)
    }

    static let dotSpan: CGFloat = 8
    static let percentSpan: CGFloat = 40

    static var labelSpan: CGFloat {
        let text = textWidth("Recording", size: 13, weight: .semibold, mono: false)
        return ceil(dotSpan + 8 + text) + 4
    }

    static func chipSpan(_ count: Int) -> CGFloat {
        let digits = textWidth("\(max(count, 1))", size: 13, weight: .semibold, mono: true)
        return ceil(digits + 5 + 17 + 16) + 4
    }

    private static func textWidth(_ text: String, size: CGFloat, weight: NSFont.Weight, mono: Bool) -> CGFloat {
        FontMetrics.width(of: text, size: size, weight: weight, mono: mono)
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
