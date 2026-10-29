import XCTest
@testable import PromptAnnotator

final class WhisperModelLocatorTests: XCTestCase {
    func testCompleteBundleIsFoundAndTokenizerIsNot() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let model = root.appendingPathComponent(
            "models/argmaxinc/whisperkit-coreml/openai_whisper-small.en_217MB",
            isDirectory: true
        )
        for stem in WhisperModelLocator.bundleStems {
            let bundle = model.appendingPathComponent("\(stem).mlmodelc", isDirectory: true)
            try FileManager.default.createDirectory(at: bundle, withIntermediateDirectories: true)
            try Data("coreml".utf8).write(to: bundle.appendingPathComponent("model.mil"))
        }
        let tokenizer = root.appendingPathComponent("models/openai/whisper-small.en", isDirectory: true)
        try FileManager.default.createDirectory(at: tokenizer, withIntermediateDirectories: true)
        try Data("{}".utf8).write(to: tokenizer.appendingPathComponent("tokenizer.json"))

        let found = try XCTUnwrap(WhisperModelLocator.locate(in: root))
        XCTAssertEqual(found.url.lastPathComponent, "openai_whisper-small.en_217MB")
        XCTAssertEqual(found.variant, WhisperModelLocator.preferredVariant)
        XCTAssertTrue(WhisperModelLocator.isComplete(found.url))
        XCTAssertFalse(WhisperModelLocator.isComplete(tokenizer))
    }

    func testIncompleteFolderIsIgnored() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let model = root.appendingPathComponent("openai_whisper-small.en_217MB", isDirectory: true)
        try FileManager.default.createDirectory(at: model, withIntermediateDirectories: true)
        try Data("x".utf8).write(to: model.appendingPathComponent("config.json"))
        XCTAssertNil(WhisperModelLocator.locate(in: root))
    }

    func testFallbackVariantIsUsedWhenThePreferredBundleIsMissing() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let model = root.appendingPathComponent("openai_whisper-small.en", isDirectory: true)
        for stem in WhisperModelLocator.bundleStems {
            let bundle = model.appendingPathComponent("\(stem).mlpackage", isDirectory: true)
            try FileManager.default.createDirectory(at: bundle, withIntermediateDirectories: true)
            try Data("w".utf8).write(to: bundle.appendingPathComponent("weights"))
        }
        let found = try XCTUnwrap(WhisperModelLocator.locate(in: root))
        XCTAssertEqual(found.variant, WhisperModelLocator.fallbackVariant)
    }

    func testInstalledModelOnThisMacIfPresent() {
        let folder = WhisperKitTranscriber.modelsFolder()
        let expected = folder.appendingPathComponent(
            "models/argmaxinc/whisperkit-coreml/openai_whisper-small.en_217MB"
        )
        guard FileManager.default.fileExists(atPath: expected.path) else { return }
        let found = WhisperModelLocator.locate(in: folder)
        XCTAssertEqual(found?.url.standardizedFileURL.path, expected.standardizedFileURL.path)
        XCTAssertEqual(found?.variant, WhisperModelLocator.preferredVariant)
        XCTAssertTrue(WhisperKitTranscriber.modelIsInstalled())
    }

    func testShorterVariantDoesNotMatchALongerFolder() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try writeCompleteModel(named: "openai_whisper-small.en_217MB", in: root)
        try writeCompleteModel(named: "openai_whisper-tiny.en", in: root)
        XCTAssertTrue(WhisperModelLocator.folderMatches("openai_whisper-small.en_217MB", variant: "small.en_217MB"))
        XCTAssertFalse(WhisperModelLocator.folderMatches("openai_whisper-small.en_217MB", variant: "small.en"))
        XCTAssertFalse(WhisperModelLocator.folderMatches("openai_whisper-large-v3_turbo", variant: "large-v3"))
        let tiny = try XCTUnwrap(WhisperModelLocator.locate(in: root, variant: "tiny.en"))
        XCTAssertEqual(tiny.variant, "tiny.en")
        let balanced = try XCTUnwrap(WhisperModelLocator.locate(in: root, variant: "small.en_217MB"))
        XCTAssertEqual(balanced.url.lastPathComponent, "openai_whisper-small.en_217MB")
        // large-v3_turbo is a catalog entry again; leftover folders still locate via WhisperModelLocator.
        XCTAssertNil(WhisperModelLocator.locate(in: root, variant: "large-v3_turbo"))
        XCTAssertNil(WhisperModelLocator.locate(in: root, variant: SpeechModelChoice.parakeetVariant))
    }

    private func writeCompleteModel(named name: String, in root: URL) throws {
        let model = root.appendingPathComponent(name, isDirectory: true)
        for stem in WhisperModelLocator.bundleStems {
            let bundle = model.appendingPathComponent("\(stem).mlmodelc", isDirectory: true)
            try FileManager.default.createDirectory(at: bundle, withIntermediateDirectories: true)
            try Data("coreml".utf8).write(to: bundle.appendingPathComponent("model.mil"))
        }
    }
}

final class LiveWordBufferTests: XCTestCase {
    func testAppendingKeepsLaterWordsAndSkipsTheBoundaryRepeat() {
        let existing = [TimedWord(text: "hello", start: 0.2, end: 0.6)]
        let incoming = [
            TimedWord(text: "hello", start: 0.21, end: 0.6),
            TimedWord(text: "there", start: 0.7, end: 1.1),
        ]
        let update = LiveWordBuffer.appending(existing, incoming, confirmedEnd: 0.6)
        XCTAssertEqual(update.words.map(\.text), ["hello", "there"])
        XCTAssertEqual(update.end, 1.1)
    }

    func testWordsInsideTheHoldbackStayUnconfirmed() {
        let duration = 2.0
        let incoming = [
            TimedWord(text: "keep", start: 0.1, end: 0.4),
            TimedWord(text: "wait", start: 1.2, end: 1.6),
        ]
        let stable = incoming.filter { $0.end <= duration - LiveWordBuffer.holdback }
        let update = LiveWordBuffer.appending([], stable, confirmedEnd: 0)
        XCTAssertEqual(update.words.map(\.text), ["keep"])
        XCTAssertEqual(LiveWordBuffer.holdback, 1)
    }

    /// Live head-cap must measure holdback from the window end, not the full buffer tail.
    func testHoldbackUsesCappedWindowEndNotFullBuffer() {
        let rate = 16_000
        let samples = Array(repeating: Float(0.1), count: rate * 90)
        let window = LiveSampleWindow.slice(
            samples: samples,
            bufferStart: 0,
            clipStart: 0,
            sampleRate: rate
        )
        let windowEnd = window.timeOffset + Double(window.samples.count) / Double(rate)
        XCTAssertEqual(windowEnd, LiveSampleWindow.maxSeconds, accuracy: 0.001)

        let incoming = [
            TimedWord(text: "early", start: 40.0, end: 40.5),
            TimedWord(text: "edge", start: 44.2, end: 44.8),
        ]
        let bufferEnd = 90.0
        let wronglyUsingBuffer = incoming.filter { $0.end <= bufferEnd - LiveWordBuffer.holdback }
        XCTAssertEqual(wronglyUsingBuffer.map(\.text), ["early", "edge"])

        let stable = incoming.filter { $0.end <= windowEnd - LiveWordBuffer.holdback }
        XCTAssertEqual(stable.map(\.text), ["early"])
    }
}
