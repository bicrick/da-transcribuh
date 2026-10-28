import XCTest
@testable import PromptAnnotator

final class WhisperModelValidatorTests: XCTestCase {
    func testCompleteFolderValidates() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let model = root.appendingPathComponent("openai_whisper-tiny.en", isDirectory: true)
        try writeCompleteModel(at: model)
        let result = WhisperModelValidator.validate(model)
        XCTAssertTrue(result.isValid)
        XCTAssertEqual(result.suggestedVariant, "tiny.en")
    }

    func testIncompleteFolderIsRejected() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let result = WhisperModelValidator.validate(root)
        XCTAssertFalse(result.isValid)
        XCTAssertTrue(result.message.contains("Missing") || result.message.contains("incomplete"))
    }

    func testHuggingFaceValidation() {
        XCTAssertFalse(WhisperModelValidator.validateHuggingFace(repo: "nope", variant: "tiny.en").isValid)
        XCTAssertFalse(WhisperModelValidator.validateHuggingFace(repo: "org/repo", variant: "").isValid)
        XCTAssertTrue(WhisperModelValidator.validateHuggingFace(repo: "argmaxinc/whisperkit-coreml", variant: "tiny.en").isValid)
    }

    private func writeCompleteModel(at model: URL) throws {
        for stem in WhisperModelLocator.bundleStems {
            let bundle = model.appendingPathComponent("\(stem).mlmodelc", isDirectory: true)
            try FileManager.default.createDirectory(at: bundle, withIntermediateDirectories: true)
            try Data("coreml".utf8).write(to: bundle.appendingPathComponent("model.mil"))
        }
    }
}

final class CustomWhisperCatalogTests: XCTestCase {
    func testUpsertSelectAndRemove() {
        let name = "PromptAnnotatorTests.customModels.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)

        let model = CustomWhisperModel(
            id: "abc",
            name: "Tiny custom",
            source: .huggingFace,
            folderBookmark: nil,
            folderPath: nil,
            hfRepo: "argmaxinc/whisperkit-coreml",
            hfVariant: "tiny.en",
            addedAt: Date()
        )
        CustomWhisperCatalog.upsert(model, defaults: defaults)
        XCTAssertEqual(CustomWhisperCatalog.load(defaults: defaults).count, 1)
        CustomWhisperCatalog.setSelectedCustomID("abc", defaults: defaults)
        XCTAssertEqual(CustomWhisperCatalog.selectedCustomID(defaults: defaults), "abc")
        CustomWhisperCatalog.remove(id: "abc", defaults: defaults)
        XCTAssertTrue(CustomWhisperCatalog.load(defaults: defaults).isEmpty)
        XCTAssertNil(CustomWhisperCatalog.selectedCustomID(defaults: defaults))
        defaults.removePersistentDomain(forName: name)
    }
}

final class WhisperSourceResolverTests: XCTestCase {
    func testBuiltInWhenNoCustomSelection() {
        let name = "PromptAnnotatorTests.source.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        defaults.set("tiny.en", forKey: SpeechModelChoice.defaultsKey)
        let source = WhisperSourceResolver.resolve(defaults: defaults)
        guard case .builtIn(let variant, let repo) = source else {
            return XCTFail("expected built-in")
        }
        XCTAssertEqual(variant, "tiny.en")
        XCTAssertEqual(repo, WhisperKitTranscriber.modelRepo)
        defaults.removePersistentDomain(forName: name)
    }

    func testHuggingFaceCustomSelection() {
        let name = "PromptAnnotatorTests.sourceHF.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        let model = CustomWhisperModel(
            id: "hf1",
            name: "Turbo",
            source: .huggingFace,
            folderBookmark: nil,
            folderPath: nil,
            hfRepo: "argmaxinc/whisperkit-coreml",
            hfVariant: "large-v3_turbo",
            addedAt: Date()
        )
        CustomWhisperCatalog.upsert(model, defaults: defaults)
        CustomWhisperCatalog.setSelectedCustomID("hf1", defaults: defaults)
        let source = WhisperSourceResolver.resolve(defaults: defaults)
        guard case .huggingFace(let repo, let variant) = source else {
            return XCTFail("expected hugging face")
        }
        XCTAssertEqual(repo, "argmaxinc/whisperkit-coreml")
        XCTAssertEqual(variant, "large-v3_turbo")
        defaults.removePersistentDomain(forName: name)
    }

    func testParakeetSelectionDoesNotBecomeWhisperKitBuiltIn() {
        let name = "PromptAnnotatorTests.sourceParakeet.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        defaults.set(SpeechModelChoice.parakeetVariant, forKey: SpeechModelChoice.defaultsKey)
        let source = WhisperSourceResolver.resolve(defaults: defaults)
        guard case .builtIn(let variant, let repo) = source else {
            return XCTFail("expected built-in WhisperKit fallback")
        }
        // RoutingTranscriber owns Parakeet; WhisperKit resolver stays on the recommended Whisper weights.
        XCTAssertEqual(variant, "small.en_217MB")
        XCTAssertEqual(repo, WhisperKitTranscriber.modelRepo)
        defaults.removePersistentDomain(forName: name)
    }
}

final class OpenAICompatibleParsingTests: XCTestCase {
    func testParsesVerboseWordArray() throws {
        let json = """
        {"text":"hello there","words":[{"word":"hello","start":0.0,"end":0.4},{"word":"there","start":0.5,"end":0.9}]}
        """.data(using: .utf8)!
        let words = try OpenAICompatibleTranscriber.parseWords(from: json)
        XCTAssertEqual(words.map(\.text), ["hello", "there"])
        XCTAssertEqual(words[0].end, 0.4, accuracy: 0.001)
    }

    func testFallsBackToPlainText() throws {
        let json = """
        {"text":"just words"}
        """.data(using: .utf8)!
        let words = try OpenAICompatibleTranscriber.parseWords(from: json)
        XCTAssertEqual(words.map(\.text), ["just words"])
    }

    func testTranscriptionURLNormalization() {
        XCTAssertEqual(
            OpenAICompatibleTranscriber.transcriptionURL(baseURL: "https://api.openai.com")?.absoluteString,
            "https://api.openai.com/v1/audio/transcriptions"
        )
        XCTAssertEqual(
            OpenAICompatibleTranscriber.transcriptionURL(baseURL: "http://127.0.0.1:8080/v1/")?.absoluteString,
            "http://127.0.0.1:8080/v1/audio/transcriptions"
        )
        XCTAssertEqual(
            OpenAICompatibleTranscriber.transcriptionURL(baseURL: "http://localhost:9000/v1/audio/transcriptions")?.absoluteString,
            "http://localhost:9000/v1/audio/transcriptions"
        )
    }
}

final class SpeechEngineKindTests: XCTestCase {
    func testDefaultsToWhisperKit() {
        XCTAssertEqual(SpeechEngineKind.stored(nil), .whisperKit)
        XCTAssertEqual(SpeechEngineKind.stored("nope"), .whisperKit)
        XCTAssertEqual(SpeechEngineKind.stored("openAICompatible"), .openAICompatible)
    }

    @MainActor
    func testSelectingBuiltInClearsCustomID() {
        let name = "PromptAnnotatorTests.engine.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        let settings = AppSettings(defaults: defaults)
        let model = CustomWhisperModel(
            id: "c1",
            name: "Custom",
            source: .huggingFace,
            folderBookmark: nil,
            folderPath: nil,
            hfRepo: "argmaxinc/whisperkit-coreml",
            hfVariant: "tiny.en",
            addedAt: Date()
        )
        settings.addCustomModel(model)
        settings.selectCustomModel("c1")
        XCTAssertEqual(settings.customModelID, "c1")
        settings.setSpeechModel("tiny.en")
        XCTAssertNil(settings.customModelID)
        XCTAssertEqual(settings.speechModel, "tiny.en")
        defaults.removePersistentDomain(forName: name)
    }
}
