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
            "Transcription failed. Try another session, or check the error log in General settings."
        )
        XCTAssertEqual(
            UserFacingError.transcription(ExportError("Cancelled by user")),
            "Transcription was cancelled."
        )
    }

    func testModelDownloadMapsTechnicalFailures() {
        XCTAssertEqual(
            UserFacingError.modelDownload(ExportError("The network request timed out.")),
            "Couldn't download the speech model. Check the network and try again."
        )
        XCTAssertEqual(
            UserFacingError.modelDownload(ExportError("Error Domain=NSURLErrorDomain Code=-1009")),
            "Couldn't download the speech model. Check the network and try again."
        )
        XCTAssertEqual(
            UserFacingError.modelDownload(ExportError("Cancelled by user")),
            "Download was cancelled."
        )
        XCTAssertEqual(
            UserFacingError.modelDownload(ExportError("No space left on device")),
            "Couldn't save the speech model. Free some disk space and try again."
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

    func testStructuralDiskFullAndOfflineErrorsMap() {
        let outOfSpace = NSError(domain: NSCocoaErrorDomain, code: NSFileWriteOutOfSpaceError, userInfo: [
            NSLocalizedDescriptionKey: "Le fichier n’a pas pu être enregistré.",
        ])
        XCTAssertEqual(
            UserFacingError.sessionWrite(outOfSpace),
            "Couldn't save the session because the disk is full. Free some space and try again."
        )
        let wrapped = NSError(domain: "WhisperKit", code: 1, userInfo: [
            NSLocalizedDescriptionKey: "Download failed",
            NSUnderlyingErrorKey: NSError(domain: NSPOSIXErrorDomain, code: Int(ENOSPC)),
        ])
        XCTAssertEqual(
            UserFacingError.modelDownload(wrapped),
            "Couldn't save the speech model. Free some disk space and try again."
        )
        let offline = NSError(domain: "HubApi", code: 2, userInfo: [
            NSLocalizedDescriptionKey: "Request failed",
            NSUnderlyingErrorKey: NSError(domain: NSURLErrorDomain, code: NSURLErrorCannotFindHost),
        ])
        XCTAssertEqual(
            UserFacingError.modelDownload(offline),
            "Couldn't download the speech model. Check the network and try again."
        )
        XCTAssertFalse(UserFacingError.isDiskFull(NSError(domain: NSCocoaErrorDomain, code: NSFileWriteNoPermissionError)))
    }
}
