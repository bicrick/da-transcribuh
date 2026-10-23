import CoreGraphics
import XCTest
@testable import PromptAnnotator

@MainActor
final class PasteModifierGateTests: XCTestCase {
    /// Manual clock and run loop so the poll is deterministic.
    private final class Harness {
        var clock: TimeInterval = 100
        var flags: CGEventFlags = []
        var pending: [(TimeInterval, () -> Void)] = []
        var fired: [TimeInterval] = []

        @MainActor func start(maxWait: TimeInterval = PasteModifierGate.maxWait) {
            PasteModifierGate.run(
                flags: { self.flags },
                now: { self.clock },
                maxWait: maxWait,
                schedule: { delay, work in self.pending.append((self.clock + delay, work)) },
                { self.fired.append(self.clock) }
            )
        }

        /// Advances to the next scheduled poll and runs it.
        @MainActor func step() {
            guard !pending.isEmpty else { return }
            let (at, work) = pending.removeFirst()
            clock = at
            work()
        }
    }

    func testPastesSynchronouslyWhenModifiersAreUp() {
        let h = Harness()
        h.start()
        XCTAssertEqual(h.fired, [100])
        XCTAssertTrue(h.pending.isEmpty)
    }

    func testShiftAloneDoesNotHoldThePaste() {
        let h = Harness()
        h.flags = [.maskShift]
        h.start()
        XCTAssertEqual(h.fired.count, 1)
    }

    func testWaitsForOptionReleaseThenPastes() {
        let h = Harness()
        h.flags = [.maskAlternate]
        h.start()
        XCTAssertTrue(h.fired.isEmpty)
        h.step(); h.step()
        XCTAssertTrue(h.fired.isEmpty)
        h.flags = []
        h.step()
        XCTAssertEqual(h.fired.count, 1)
        XCTAssertEqual(h.fired[0] - 100, 3 * PasteModifierGate.pollInterval, accuracy: 1e-9)
        XCTAssertTrue(h.pending.isEmpty)
    }

    func testHeldModifierIsCappedAtMaxWait() {
        let h = Harness()
        h.flags = [.maskCommand, .maskControl]
        h.start()
        for _ in 0..<100 where h.fired.isEmpty { h.step() }
        XCTAssertEqual(h.fired.count, 1)
        XCTAssertGreaterThanOrEqual(h.fired[0] - 100, PasteModifierGate.maxWait - 1e-9)
        XCTAssertLessThan(h.fired[0] - 100, PasteModifierGate.maxWait + PasteModifierGate.pollInterval + 1e-9)
        XCTAssertTrue(h.pending.isEmpty)
    }

    func testIsClear() {
        XCTAssertTrue(PasteModifierGate.isClear([]))
        XCTAssertTrue(PasteModifierGate.isClear([.maskShift, .maskAlphaShift]))
        XCTAssertFalse(PasteModifierGate.isClear([.maskAlternate]))
        XCTAssertFalse(PasteModifierGate.isClear([.maskCommand]))
        XCTAssertFalse(PasteModifierGate.isClear([.maskControl]))
    }
}
