import Foundation

struct WhisperModelValidation: Equatable, Sendable {
    var isValid: Bool
    var message: String
    /// Best-effort variant label derived from the folder name.
    var suggestedVariant: String
}

enum WhisperModelValidator {
    /// Accepts a WhisperKit Core ML folder (MelSpectrogram + AudioEncoder + TextDecoder).
    static func validate(_ folder: URL) -> WhisperModelValidation {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: folder.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            return WhisperModelValidation(
                isValid: false,
                message: "That path is not a folder.",
                suggestedVariant: folder.lastPathComponent
            )
        }

        let missing = WhisperModelLocator.bundleStems.filter { stem in
            !hasBundle(stem, in: folder)
        }
        if !missing.isEmpty {
            return WhisperModelValidation(
                isValid: false,
                message: "Missing Core ML bundles: \(missing.joined(separator: ", ")). Export a WhisperKit model (MelSpectrogram, AudioEncoder, TextDecoder).",
                suggestedVariant: suggestedVariant(for: folder)
            )
        }

        guard WhisperModelLocator.isComplete(folder) else {
            return WhisperModelValidation(
                isValid: false,
                message: "The Core ML bundles look incomplete (no model weights). Re-export or pick another folder.",
                suggestedVariant: suggestedVariant(for: folder)
            )
        }

        return WhisperModelValidation(
            isValid: true,
            message: "Ready to use.",
            suggestedVariant: suggestedVariant(for: folder)
        )
    }

    static func validateHuggingFace(repo: String, variant: String) -> WhisperModelValidation {
        let trimmedRepo = repo.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedVariant = variant.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedRepo.isEmpty || !trimmedRepo.contains("/") {
            return WhisperModelValidation(
                isValid: false,
                message: "Use a Hugging Face repo id like argmaxinc/whisperkit-coreml.",
                suggestedVariant: trimmedVariant
            )
        }
        if trimmedVariant.isEmpty {
            return WhisperModelValidation(
                isValid: false,
                message: "Enter the model variant folder name (for example small.en_217MB).",
                suggestedVariant: trimmedVariant
            )
        }
        if trimmedRepo.count > 200 || trimmedVariant.count > 120 {
            return WhisperModelValidation(
                isValid: false,
                message: "Repo or variant name is too long.",
                suggestedVariant: String(trimmedVariant.prefix(120))
            )
        }
        return WhisperModelValidation(
            isValid: true,
            message: "Ready to download.",
            suggestedVariant: trimmedVariant
        )
    }

    private static func hasBundle(_ stem: String, in folder: URL) -> Bool {
        ["mlmodelc", "mlpackage"].contains { ext in
            let bundle = folder.appendingPathComponent("\(stem).\(ext)", isDirectory: true)
            var isDirectory: ObjCBool = false
            return FileManager.default.fileExists(atPath: bundle.path, isDirectory: &isDirectory)
                && isDirectory.boolValue
        }
    }

    static func suggestedVariant(for folder: URL) -> String {
        let name = folder.lastPathComponent
        if let range = name.range(of: "whisper-", options: .caseInsensitive) {
            return String(name[range.upperBound...])
        }
        if name.hasPrefix("openai_whisper-") {
            return String(name.dropFirst("openai_whisper-".count))
        }
        return name
    }
}
