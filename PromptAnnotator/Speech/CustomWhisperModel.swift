import Foundation

/// A user-added WhisperKit Core ML model (local folder or Hugging Face download).
struct CustomWhisperModel: Codable, Identifiable, Equatable, Sendable {
    enum Source: String, Codable, Sendable {
        case folder
        case huggingFace
    }

    var id: String
    var name: String
    var source: Source
    /// Security-scoped bookmark for a user-picked folder.
    var folderBookmark: Data?
    /// Display / fallback path for folder models.
    var folderPath: String?
    var hfRepo: String?
    var hfVariant: String?
    var addedAt: Date

    var subtitle: String {
        switch source {
        case .folder:
            return folderPath ?? "Local Core ML folder"
        case .huggingFace:
            let repo = hfRepo ?? "—"
            let variant = hfVariant ?? "—"
            return "\(repo) · \(variant)"
        }
    }
}

/// Persists custom WhisperKit models in Application Support + UserDefaults index.
enum CustomWhisperCatalog {
    static let defaultsKey = "speech.customModels"
    static let selectedCustomIDKey = "speech.customModelID"

    nonisolated static func load(defaults: UserDefaults = .standard) -> [CustomWhisperModel] {
        guard let data = defaults.data(forKey: defaultsKey) else { return [] }
        return (try? JSONDecoder().decode([CustomWhisperModel].self, from: data)) ?? []
    }

    nonisolated static func save(_ models: [CustomWhisperModel], defaults: UserDefaults = .standard) {
        guard let data = try? JSONEncoder().encode(models) else { return }
        defaults.set(data, forKey: defaultsKey)
    }

    nonisolated static func selectedCustomID(defaults: UserDefaults = .standard) -> String? {
        let value = defaults.string(forKey: selectedCustomIDKey) ?? ""
        return value.isEmpty ? nil : value
    }

    nonisolated static func setSelectedCustomID(_ id: String?, defaults: UserDefaults = .standard) {
        if let id, !id.isEmpty {
            defaults.set(id, forKey: selectedCustomIDKey)
        } else {
            defaults.removeObject(forKey: selectedCustomIDKey)
        }
    }

    nonisolated static func model(id: String, defaults: UserDefaults = .standard) -> CustomWhisperModel? {
        load(defaults: defaults).first { $0.id == id }
    }

    nonisolated static func upsert(_ model: CustomWhisperModel, defaults: UserDefaults = .standard) {
        var models = load(defaults: defaults)
        if let index = models.firstIndex(where: { $0.id == model.id }) {
            models[index] = model
        } else {
            models.append(model)
        }
        save(models, defaults: defaults)
    }

    nonisolated static func remove(id: String, defaults: UserDefaults = .standard) {
        var models = load(defaults: defaults)
        models.removeAll { $0.id == id }
        save(models, defaults: defaults)
        if selectedCustomID(defaults: defaults) == id {
            setSelectedCustomID(nil, defaults: defaults)
        }
    }
}
