import XCTest
@testable import PromptAnnotator

/// The preview never outlives the list: every close path hides it and stale shows are refused.
@MainActor
final class ClipboardPreviewOwnerTests: XCTestCase {
    private var shown: [String] = []
    private var hides: [Bool] = []
    private var owner: ClipboardPreviewOwner<String>!

    override func setUp() async throws {
        shown = []
        hides = []
        owner = ClipboardPreviewOwner<String>(
            show: { [unowned self] in self.shown.append($0) },
            hide: { [unowned self] in self.hides.append($0) }
        )
    }

    func testShowWhileOpen() {
        let token = owner.listOpened()
        owner.request("a", token: token)
        XCTAssertEqual(shown, ["a"])
    }

    func testEveryDismissalHidesPreviewAndRefusesPendingShow() {
        for reason in ClipboardListDismissal.allCases {
            shown = []
            hides = []
            let token = owner.listOpened()
            owner.request("before", token: token)
            let animated = reason != .pick
            owner.listClosed(reason, animated: animated)
            XCTAssertEqual(hides, [animated], "\(reason) must hide the preview once")
            XCTAssertFalse(owner.isListOpen, "\(reason)")
            // A debounced hover or arrow-key show that lands after the close.
            owner.request("late", token: token)
            XCTAssertEqual(shown, ["before"], "\(reason) let a late show through")
        }
    }

    func testCloseDuringPendingDelayedShow() async {
        let token = owner.listOpened()
        // Same shape as the view's hover debounce: a Task that sleeps, then shows.
        let pending = Task { @MainActor [owner] in
            try? await Task.sleep(nanoseconds: 60_000_000)
            owner?.request("delayed", token: token)
        }
        owner.listClosed(.escape, animated: true)
        await pending.value
        XCTAssertTrue(shown.isEmpty)
        XCTAssertEqual(hides, [true])
    }

    func testCloseDuringPendingShowViaHotkeyToggleThenReopen() async {
        let first = owner.listOpened()
        let pending = Task { @MainActor [owner] in
            try? await Task.sleep(nanoseconds: 60_000_000)
            owner?.request("from-first-open", token: first)
        }
        owner.listClosed(.hotkeyToggle, animated: true)
        // Reopened before the old debounce fired: the old request is still stale.
        let second = owner.listOpened()
        await pending.value
        XCTAssertTrue(shown.isEmpty)
        owner.request("fresh", token: second)
        XCTAssertEqual(shown, ["fresh"])
    }

    func testNilRequestHides() {
        let token = owner.listOpened()
        owner.request(nil, token: token)
        XCTAssertEqual(hides, [true])
        XCTAssertTrue(shown.isEmpty)
    }

    func testRequestBeforeAnyOpenIsRefused() {
        owner.request("x", token: 0)
        owner.request("y", token: owner.session)
        XCTAssertTrue(shown.isEmpty)
    }
}
