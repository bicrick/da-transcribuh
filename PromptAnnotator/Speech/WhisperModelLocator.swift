import Foundation

struct WhisperModelFolder: Equatable, Sendable {
    var url: URL
    var variant: String
}

enum WhisperModelLocator {
    static let preferredVariant = "small.en_217MB"
    static let fallbackVariant = "small.en"
    static let bundleStems = ["MelSpectrogram", "AudioEncoder", "TextDecoder"]

    /// Finds one complete model. With no variant, the default `small.en_217MB` wins,
    /// then `small.en`. A shorter name does not match a longer one: `small.en` is not
    /// `small.en_217MB`, and `large-v3` is not `large-v3_turbo`.
    static func locate(in root: URL, variant: String? = nil) -> WhisperModelFolder? {
        let folders = completeFolders(in: root)
        if let variant {
            if let match = folders.first(where: { folderMatches($0.lastPathComponent, variant: variant) }) {
                return WhisperModelFolder(url: match, variant: variant)
            }
            if variant == preferredVariant,
               let fallback = folders.first(where: { folderMatches($0.lastPathComponent, variant: fallbackVariant) }) {
                return WhisperModelFolder(url: fallback, variant: fallbackVariant)
            }
            return nil
        }
        if let preferred = folders.first(where: { folderMatches($0.lastPathComponent, variant: preferredVariant) }) {
            return WhisperModelFolder(url: preferred, variant: preferredVariant)
        }
        if let fallback = folders.first(where: { folderMatches($0.lastPathComponent, variant: fallbackVariant) }) {
            return WhisperModelFolder(url: fallback, variant: fallbackVariant)
        }
        return nil
    }

    static func folderMatches(_ name: String, variant: String) -> Bool {
        name.contains(variant) && !name.contains(variant + "_")
    }

    private static func completeFolders(in root: URL) -> [URL] {
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }
        var folders: [URL] = []
        for case let url as URL in enumerator {
            let values = try? url.resourceValues(forKeys: [.isDirectoryKey])
            guard values?.isDirectory == true, isComplete(url) else { continue }
            folders.append(url)
        }
        return folders
    }

    static func isComplete(_ folder: URL) -> Bool {
        bundleStems.allSatisfy { stem in
            ["mlmodelc", "mlpackage"].contains { ext in
                let bundle = folder.appendingPathComponent("\(stem).\(ext)", isDirectory: true)
                var isDirectory: ObjCBool = false
                guard FileManager.default.fileExists(atPath: bundle.path, isDirectory: &isDirectory), isDirectory.boolValue else {
                    return false
                }
                return FileManager.default.fileExists(atPath: bundle.appendingPathComponent("model.mil").path)
                    || FileManager.default.fileExists(atPath: bundle.appendingPathComponent("coremldata.bin").path)
                    || FileManager.default.fileExists(atPath: bundle.appendingPathComponent("weights").path)
            }
        }
    }
}
