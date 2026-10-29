import Foundation

/// Where WhisperKit should load weights from for the current selection.
enum WhisperSource: Equatable, Sendable {
    case builtIn(variant: String, repo: String)
    case folder(url: URL, label: String, bookmark: Data?)
    case huggingFace(repo: String, variant: String)

    var displayName: String {
        switch self {
        case .builtIn(let variant, _):
            return variant
        case .folder(_, let label, _):
            return label
        case .huggingFace(let repo, let variant):
            return "\(repo)/\(variant)"
        }
    }

    var variantLabel: String {
        switch self {
        case .builtIn(let variant, _):
            return variant
        case .folder(_, let label, _):
            return label
        case .huggingFace(_, let variant):
            return variant
        }
    }

    var modelRepo: String {
        switch self {
        case .builtIn(_, let repo):
            return repo
        case .folder:
            return WhisperKitTranscriber.modelRepo
        case .huggingFace(let repo, _):
            return repo
        }
    }
}

enum WhisperSourceResolver {
    /// Resolves the active WhisperKit source from UserDefaults / custom catalog.
    /// Falls back to the built-in balanced model when a custom entry is missing or invalid.
    nonisolated static func resolve(defaults: UserDefaults = .standard) -> WhisperSource {
        if let customID = CustomWhisperCatalog.selectedCustomID(defaults: defaults),
           let custom = CustomWhisperCatalog.model(id: customID, defaults: defaults) {
            switch custom.source {
            case .folder:
                if let url = resolveFolderURL(custom) {
                    let label = custom.name.isEmpty
                        ? WhisperModelValidator.suggestedVariant(for: url)
                        : custom.name
                    return .folder(url: url, label: label, bookmark: custom.folderBookmark)
                }
            case .huggingFace:
                let repo = (custom.hfRepo ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                let variant = (custom.hfVariant ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                if WhisperModelValidator.validateHuggingFace(repo: repo, variant: variant).isValid {
                    return .huggingFace(repo: repo, variant: variant)
                }
            }
        }

        let choice = SpeechModelChoice.stored(defaults.string(forKey: SpeechModelChoice.defaultsKey))
        // Parakeet is routed by RoutingTranscriber; WhisperKit only sees Whisper backends.
        let variant = choice.backend == .whisperKit
            ? choice.variant
            : SpeechModelChoice.recommended.variant
        return .builtIn(variant: variant, repo: WhisperKitTranscriber.modelRepo)
    }

    nonisolated static func resolveFolderURL(_ model: CustomWhisperModel) -> URL? {
        if let bookmark = model.folderBookmark {
            var isStale = false
            if let url = try? URL(
                resolvingBookmarkData: bookmark,
                options: [.withSecurityScope, .withoutUI],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            ) {
                return url
            }
        }
        if let path = model.folderPath, !path.isEmpty {
            return URL(fileURLWithPath: path, isDirectory: true)
        }
        return nil
    }
}
