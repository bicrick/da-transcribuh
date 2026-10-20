import CoreGraphics
import Foundation

/// How the comb moves once recording has stopped.
/// A couple of low ripples travel across the slots. The bars stay put.
enum WaveformMotion {
    static func loading(frame: Int, count: Int = WaveformSamples.count) -> [CGFloat] {
        loading(time: Double(frame) / 30.0, count: count)
    }

    static func loading(time: TimeInterval, count: Int = WaveformSamples.count) -> [CGFloat] {
        guard count > 0 else { return [] }
        let travel = time * 0.48
        let span = Double(max(count - 1, 1))
        return (0..<count).map { index in
            let x = Double(index) / span
            let lead = hump(x, center: wrap(travel), width: 0.22)
            let follow = hump(x, center: wrap(travel + 0.42), width: 0.16)
            let level = 0.10 + lead * 0.34 + follow * 0.20
            return CGFloat(min(1, max(0.08, level)))
        }
    }

    /// Smoothstep from the recording shape into the ripple. Zero at the start, one after `duration`.
    static func blend(_ elapsed: TimeInterval, duration: TimeInterval = 0.5) -> CGFloat {
        guard duration > 0 else { return 1 }
        let x = max(0, min(1, elapsed / duration))
        return CGFloat(x * x * (3 - 2 * x))
    }

    static func mix(_ from: [CGFloat], _ to: [CGFloat], amount: CGFloat) -> [CGFloat] {
        let amount = min(1, max(0, amount))
        let count = max(from.count, to.count)
        return (0..<count).map { index in
            let start = index < from.count ? from[index] : 0.1
            let end = index < to.count ? to[index] : 0.1
            return start + (end - start) * amount
        }
    }

    private static func wrap(_ value: Double) -> Double {
        let wrapped = value.truncatingRemainder(dividingBy: 1)
        return wrapped < 0 ? wrapped + 1 : wrapped
    }

    /// One soft hill. The ends of the comb connect, so a ripple can leave one side and enter the other.
    private static func hump(_ x: Double, center: Double, width: Double) -> Double {
        var delta = abs(x - center)
        if delta > 0.5 { delta = 1 - delta }
        let half = width / 2
        guard delta < half, half > 0 else { return 0 }
        return 0.5 + 0.5 * cos(delta / half * .pi)
    }
}
