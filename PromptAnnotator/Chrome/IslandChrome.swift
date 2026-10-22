import AppKit
import SwiftUI

/// How open each piece of recording chrome is. Zero is gone, one is fully in the capsule.
/// Left slot = record square + timer. Right slot = capture chip (or download %) — fully collapsed at 0.
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

/// Per-style chrome scale. Default (classic) matches the former compact footprint;
/// compact is tighter still. Hit targets stay ≥24pt.
struct IslandChromeScale: Equatable {
    var inset: CGFloat
    var sideGap: CGFloat
    var recordSize: CGFloat
    var recordClockGap: CGFloat
    var clockFontSize: CGFloat
    var chipFontSize: CGFloat
    var chipIconSize: CGFloat
    var chipMinHeight: CGFloat
    var barHeight: CGFloat
    var wave: CGSize
    var percentSpan: CGFloat

    var clockSpan: CGFloat {
        let m = IslandMetrics.textWidth("59:59", size: clockFontSize)
        let h = IslandMetrics.textWidth("9:59:59", size: clockFontSize)
        return max(m, h) + 2
    }

    func chipSpan(_ count: Int) -> CGFloat {
        let digits = IslandMetrics.textWidth("\(max(count, 1))", size: chipFontSize)
        let hPad = chipMinHeight >= 28 ? Ink.space2 : Ink.space1 + 2
        return ceil(digits + 6 + chipIconSize + hPad * 2) + 2
    }

    var leadingNatural: CGFloat {
        recordSize + recordClockGap + clockSpan
    }
}

/// Sizes for the capsule. Trailing slot collapses to zero when there are no captures.
/// `panel` is the bar face; `chrome` adds the double-pane gutter (`Ink.buttonShadow`).
struct IslandLayout: Equatable {
    var panel = CGSize(width: 280, height: 48)
    /// NSPanel frame — bar + hard offset gutter so the pane isn’t clipped.
    var chrome = CGSize(width: 282, height: 50)
    var leadingSide: CGFloat = 0
    var trailingSide: CGFloat = 0
    var wave = CGSize(width: 188, height: 26)
    var sideGapLeading: CGFloat = 0
    var sideGapTrailing: CGFloat = 0
    var record: CGFloat = 0
    var clock: CGFloat = 0
    var recordClockGap: CGFloat = 0
    var chip: CGFloat = 0
    var percent: CGFloat = 0
    var scale = IslandMetrics.scale(for: .classic)
}

enum IslandMetrics {
    /// Default (classic) — former compact footprint.
    static func scale(for style: IslandStyle) -> IslandChromeScale {
        switch style {
        case .classic:
            return IslandChromeScale(
                inset: 14,
                sideGap: 12,
                recordSize: 8,
                recordClockGap: 8,
                clockFontSize: 12,
                chipFontSize: 12,
                chipIconSize: 10,
                chipMinHeight: 28,
                barHeight: 48,
                wave: CGSize(width: 188, height: 26),
                percentSpan: 40
            )
        case .compact:
            return IslandChromeScale(
                inset: 10,
                sideGap: 8,
                recordSize: 7,
                recordClockGap: 6,
                clockFontSize: 11,
                chipFontSize: 11,
                chipIconSize: 9,
                chipMinHeight: 24,
                barHeight: 36,
                wave: CGSize(width: 136, height: 18),
                percentSpan: 36
            )
        case .minimal:
            return IslandChromeScale(
                inset: 12,
                sideGap: 0,
                recordSize: 8,
                recordClockGap: 8,
                clockFontSize: 12,
                chipFontSize: 12,
                chipIconSize: 10,
                chipMinHeight: 24,
                barHeight: 40,
                wave: CGSize(width: 200, height: 22),
                percentSpan: 40
            )
        case .hidden:
            return IslandChromeScale(
                inset: 12,
                sideGap: 0,
                recordSize: 8,
                recordClockGap: 8,
                clockFontSize: 12,
                chipFontSize: 12,
                chipIconSize: 10,
                chipMinHeight: 24,
                barHeight: 40,
                wave: CGSize(width: 200, height: 22),
                percentSpan: 40
            )
        }
    }

    /// Convenience for tests / callers that mean the default size.
    static var inset: CGFloat { scale(for: .classic).inset }
    static var sideGap: CGFloat { scale(for: .classic).sideGap }
    static var recordSize: CGFloat { scale(for: .classic).recordSize }
    static var clockFontSize: CGFloat { scale(for: .classic).clockFontSize }
    static var chipFontSize: CGFloat { scale(for: .classic).chipFontSize }
    static var chipIconSize: CGFloat { scale(for: .classic).chipIconSize }
    static var fixedClockSpan: CGFloat { scale(for: .classic).clockSpan }

    static func layout(
        style: IslandStyle,
        slots: IslandSlots,
        captures: Int,
        elapsed: TimeInterval
    ) -> IslandLayout {
        _ = elapsed
        let scale = scale(for: style)
        let leadingOpen = max(slots.dot, slots.clock)
        let trailingOpen = max(slots.chip, slots.percent)

        let leadingNatural = scale.leadingNatural
        let trailingNatural = max(scale.chipSpan(max(captures, 1)), scale.percentSpan)
        // When a trailing slot is present, both sides share one width so the wave stays centered.
        let sideEqual = max(leadingNatural, trailingNatural)

        let leadingSide: CGFloat
        let trailingSide: CGFloat
        if trailingOpen < 0.001 {
            // No captures / no percent — collapse trailing fully; no reserved width.
            leadingSide = leadingNatural * leadingOpen
            trailingSide = 0
        } else {
            // Interpolate left up to the equal side as the chip opens; right grows from 0.
            leadingSide = (leadingNatural + (sideEqual - leadingNatural) * trailingOpen) * leadingOpen
            trailingSide = sideEqual * trailingOpen
        }

        let gapL = scale.sideGap * leadingOpen
        let gapR = scale.sideGap * trailingOpen

        let panel = CGSize(
            width: scale.inset * 2 + leadingSide + gapL + scale.wave.width + gapR + trailingSide,
            height: scale.barHeight
        )
        let gutter = Ink.buttonShadow
        let chrome = CGSize(width: panel.width + gutter, height: panel.height + gutter)
        return IslandLayout(
            panel: panel,
            chrome: chrome,
            leadingSide: leadingSide,
            trailingSide: trailingSide,
            wave: scale.wave,
            sideGapLeading: gapL,
            sideGapTrailing: gapR,
            record: scale.recordSize * leadingOpen,
            clock: scale.clockSpan * slots.clock,
            recordClockGap: scale.recordClockGap * slots.clock,
            chip: scale.chipSpan(captures) * slots.chip,
            percent: scale.percentSpan * slots.percent,
            scale: scale
        )
    }

    static func waveformWidth(_ style: IslandStyle) -> CGFloat {
        scale(for: style).wave.width
    }

    static func waveformHeight(_ style: IslandStyle) -> CGFloat {
        scale(for: style).wave.height
    }

    static func barHeight(_ style: IslandStyle) -> CGFloat {
        scale(for: style).barHeight
    }

    static func clockSpan(_ elapsed: TimeInterval) -> CGFloat {
        _ = elapsed
        return fixedClockSpan
    }

    static func clockSpan(style: IslandStyle, elapsed: TimeInterval) -> CGFloat {
        _ = elapsed
        return scale(for: style).clockSpan
    }

    static let percentSpan: CGFloat = 40

    static func chipSpan(_ count: Int) -> CGFloat {
        scale(for: .classic).chipSpan(count)
    }

    static func textWidth(_ text: String, size: CGFloat) -> CGFloat {
        FontMetrics.width(of: text, size: size, weight: .regular, mono: true)
    }
}

/// Eases the side pieces. Tau ~0.07 → chip expand/collapse lands in ~0.2–0.25s.
@MainActor
final class IslandChromeMotion: ObservableObject {
    @Published private(set) var presence: IslandPresence = .hidden
    @Published private(set) var slots = IslandSlots()

    var onFrame: (() -> Void)?
    private(set) var isAnimating = false

    private var targets = IslandSlots()
    private var timer: Timer?
    private var lastTick: CFTimeInterval = 0
    /// Chip open/close ease (~0.22s to settle).
    private let tau: TimeInterval = 0.07

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
        let next = slots.approached(toward: targets, delta: delta, tau: tau)
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
