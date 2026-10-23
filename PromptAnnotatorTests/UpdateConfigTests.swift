import XCTest
@testable import PromptAnnotator

/// Sparkle settings baked into Info.plist. Beta ships with automatic checks off.
final class UpdateConfigTests: XCTestCase {
    func testFeedPointsAtTheLatestReleaseAppcast() {
        XCTAssertEqual(
            UpdateController.Config.feedURL,
            "https://github.com/bicrick/da-transcribuh/releases/latest/download/appcast.xml"
        )
    }

    func testPublicEDKeyIsAnEd25519PublicKey() throws {
        let key = try XCTUnwrap(UpdateController.Config.publicEDKey)
        XCTAssertEqual(key.count, 44)
        XCTAssertEqual(Data(base64Encoded: key)?.count, 32)
    }

    func testAutomaticChecksStayOffAndTheFeedMustBeSigned() {
        XCTAssertFalse(UpdateController.Config.automaticChecksEnabled)
        XCTAssertEqual(Bundle.main.object(forInfoDictionaryKey: "SUAutomaticallyUpdate") as? Bool, false)
        XCTAssertTrue(UpdateController.Config.requiresSignedFeed)
    }

    @MainActor
    func testUpdaterNeverStartsUnderUnitTests() {
        XCTAssertFalse(UpdateController.shared.canCheckForUpdates)
        XCTAssertFalse(UpdateController.shared.automaticallyChecksForUpdates)
        XCTAssertEqual(UpdateController.menuTitle, "Check for Updates…")
    }
}
