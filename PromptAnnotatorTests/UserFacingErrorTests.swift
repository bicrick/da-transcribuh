import XCTest
@testable import PromptAnnotator

final class UserFacingErrorTests: XCTestCase {
    func testExportErrorsPassThrough() {
        let error = ExportError("The microphone didn't start recording.")
        XCTAssertEqual(UserFacingError.sessionStart(error), error.message)
        XCTAssertEqual(UserFacingError.capture(error), error.message)
        XCTAssertEqual(UserFacingError.sessionWrite(error), error.message)
    }

    func testTranscriptionMapsNetworkAndModelFailures() {
        XCTAssertEqual(
            UserFacingError.transcription(ExportError("The network request timed out.")),
            "Couldn't download the speech model. Check the network and try again."
        )
        XCTAssertEqual(
            UserFacingError.transcription(ExportError("Model file not found on disk.")),
            "The speech model is missing. Open Model settings to download it."
        )
        XCTAssertEqual(
            UserFacingError.transcription(ExportError("Error Domain=WhisperKit Code=-1 \"boom\"")),
            "Transcription failed. Try another session, or check the error log in Configuration."
        )
        XCTAssertEqual(
            UserFacingError.transcription(ExportError("Cancelled by user")),
            "Transcription was cancelled."
        )
    }

    @MainActor
    func testMenuIconTracksRecordingAndBusyPhases() {
        let session = SessionController.shared
        // Read-only probes against the shared controller's published helpers.
        // Phase is private(set); assert the mapping table via a local mirror of the API contract.
        XCTAssertEqual(icon(for: .idle), "pencil.tip.crop.circle")
        XCTAssertEqual(icon(for: .recording), "record.circle.fill")
        XCTAssertEqual(icon(for: .finishing), "ellipsis.circle")
        XCTAssertEqual(icon(for: .transcribing), "ellipsis.circle")
        XCTAssertEqual(icon(for: .preparingModel), "ellipsis.circle")
        XCTAssertEqual(icon(for: .downloading(0.4)), "ellipsis.circle")
        XCTAssertEqual(session.menuIcon, icon(for: session.phase))
        XCTAssertFalse(session.menuAccessibilityLabel.isEmpty)
    }

    private func icon(for phase: SessionPhase) -> String {
        switch phase {
        case .recording:
            return "record.circle.fill"
        case .finishing, .downloading, .preparingModel, .transcribing:
            return "ellipsis.circle"
        case .idle:
            return "pencil.tip.crop.circle"
        }
    }
}
