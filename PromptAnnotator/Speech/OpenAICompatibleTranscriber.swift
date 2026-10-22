import Foundation
import os

/// Final-pass transcription via OpenAI-compatible `POST /v1/audio/transcriptions`.
/// Live `consume` is a no-op — captions stay off while this engine is selected.
actor OpenAICompatibleTranscriber: Transcribing {
    static let baseURLKey = "speech.openai.baseURL"
    static let modelKey = "speech.openai.model"

    private let log = Logger(subsystem: "com.bicrick.PromptAnnotator", category: "openai-speech")
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    nonisolated func resetLive() {}

    func prepare() async {}

    func consume(samples: [Float], bufferStart: TimeInterval, absoluteEndCount: Int) async {}

    func transcribe(
        audioURL: URL,
        samples: [Float],
        onProgress: @escaping @Sendable (SpeechProgress) -> Void
    ) async throws -> Transcript {
        onProgress(.preparing)
        let config = try Self.loadConfig()
        onProgress(.transcribing)

        let boundary = "MutterBoundary\(UUID().uuidString.replacingOccurrences(of: "-", with: ""))"
        var request = URLRequest(url: config.endpoint)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 120

        let body = try Self.multipartBody(
            boundary: boundary,
            fileURL: audioURL,
            model: config.model
        )
        request.httpBody = body

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw ExportError("The transcription server returned an invalid response.")
        }
        guard (200...299).contains(http.statusCode) else {
            let snippet = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let short = snippet.isEmpty ? "HTTP \(http.statusCode)" : String(snippet.prefix(160))
            throw ExportError("Transcription server error: \(short)")
        }

        let words = try Self.parseWords(from: data)
        let label = "openai:\(config.model)"
        return Transcript(words: NonSpeechFilter.filterWords(words), model: label)
    }

    nonisolated static func storedBaseURL(defaults: UserDefaults = .standard) -> String {
        let raw = defaults.string(forKey: baseURLKey) ?? ""
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "https://api.openai.com" : trimmed
    }

    nonisolated static func storedModel(defaults: UserDefaults = .standard) -> String {
        let raw = defaults.string(forKey: modelKey) ?? ""
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "whisper-1" : trimmed
    }

    nonisolated static func isConfigured(defaults: UserDefaults = .standard) -> Bool {
        let key = KeychainStore.get(account: KeychainStore.openAIAPIKeyAccount) ?? ""
        return !key.isEmpty
    }

    private struct Config: Sendable {
        var endpoint: URL
        var apiKey: String
        var model: String
    }

    private nonisolated static func loadConfig(defaults: UserDefaults = .standard) throws -> Config {
        let base = storedBaseURL(defaults: defaults)
        guard let endpoint = transcriptionURL(baseURL: base) else {
            throw ExportError("The OpenAI-compatible base URL is not valid.")
        }
        let key = KeychainStore.get(account: KeychainStore.openAIAPIKeyAccount) ?? ""
        guard !key.isEmpty else {
            throw ExportError("Add an API key in Model settings for the OpenAI-compatible server.")
        }
        return Config(endpoint: endpoint, apiKey: key, model: storedModel(defaults: defaults))
    }

    nonisolated static func transcriptionURL(baseURL: String) -> URL? {
        var trimmed = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        while trimmed.hasSuffix("/") {
            trimmed.removeLast()
        }
        if trimmed.hasSuffix("/v1/audio/transcriptions") {
            return URL(string: trimmed)
        }
        if trimmed.hasSuffix("/v1") {
            return URL(string: trimmed + "/audio/transcriptions")
        }
        return URL(string: trimmed + "/v1/audio/transcriptions")
    }

    private nonisolated static func multipartBody(
        boundary: String,
        fileURL: URL,
        model: String
    ) throws -> Data {
        let fileData = try Data(contentsOf: fileURL)
        let rawName = fileURL.lastPathComponent.isEmpty ? "audio.m4a" : fileURL.lastPathComponent
        let filename = rawName
            .replacingOccurrences(of: "\"", with: "")
            .replacingOccurrences(of: "\r", with: "")
            .replacingOccurrences(of: "\n", with: "")
        var body = Data()
        func append(_ text: String) {
            if let data = text.data(using: .utf8) {
                body.append(data)
            }
        }
        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"model\"\r\n\r\n")
        append("\(model)\r\n")
        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"response_format\"\r\n\r\n")
        append("verbose_json\r\n")
        // Avoid timestamp_granularities[] — many local compatible servers reject unknown fields.
        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"file\"; filename=\"\(filename)\"\r\n")
        append("Content-Type: application/octet-stream\r\n\r\n")
        body.append(fileData)
        append("\r\n")
        append("--\(boundary)--\r\n")
        return body
    }

    /// Parses verbose_json words, or falls back to a single span from `text`.
    nonisolated static func parseWords(from data: Data) throws -> [TimedWord] {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ExportError("The transcription server returned non-JSON data.")
        }
        if let words = json["words"] as? [[String: Any]] {
            let timed: [TimedWord] = words.compactMap { entry in
                let text = (entry["word"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
                guard let text, !text.isEmpty else { return nil }
                let start = doubleValue(entry["start"]) ?? 0
                let end = doubleValue(entry["end"]) ?? start
                return TimedWord(text: text, start: start, end: max(end, start))
            }
            if !timed.isEmpty { return timed }
        }
        if let segments = json["segments"] as? [[String: Any]] {
            var timed: [TimedWord] = []
            for segment in segments {
                if let words = segment["words"] as? [[String: Any]] {
                    for entry in words {
                        let text = (entry["word"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard let text, !text.isEmpty else { continue }
                        let start = doubleValue(entry["start"]) ?? 0
                        let end = doubleValue(entry["end"]) ?? start
                        timed.append(TimedWord(text: text, start: start, end: max(end, start)))
                    }
                } else if let text = (segment["text"] as? String)?
                    .trimmingCharacters(in: .whitespacesAndNewlines),
                    !text.isEmpty {
                    let start = doubleValue(segment["start"]) ?? 0
                    let end = doubleValue(segment["end"]) ?? start
                    timed.append(TimedWord(text: text, start: start, end: max(end, start)))
                }
            }
            if !timed.isEmpty { return timed }
        }
        let text = (json["text"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !text.isEmpty else { return [] }
        return [TimedWord(text: text, start: 0, end: 0.01)]
    }

    private nonisolated static func doubleValue(_ any: Any?) -> Double? {
        if let value = any as? Double { return value }
        if let value = any as? Int { return Double(value) }
        if let value = any as? NSNumber { return value.doubleValue }
        if let value = any as? String { return Double(value) }
        return nil
    }
}
