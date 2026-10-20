import Foundation

struct WhisperModelFolder: Equatable, Sendable {
    var url: URL
    var variant: String
}

enum WhisperModelLocator {
    static let preferredVariant = "small.en_217MB"
    static let fallbackVariant = "small.en"
    static let bundleStems = ["MelSpectrogram", "AudioEncoder", "TextDecoder"]

    static func locate(in root: URL) -> WhisperModelFolder? {
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return nil
        }

        var preferred: URL?
        var fallback: URL?
        for case let url as URL in enumerator {
            let values = try? url.resourceValues(forKeys: [.isDirectoryKey])
            guard values?.isDirectory == true, isComplete(url) else { continue }
            let name = url.lastPathComponent
            if name.contains(preferredVariant) {
                preferred = url
                break
            }
            if name.contains(fallbackVariant), fallback == nil {
                fallback = url
            }
        }

        if let preferred {
            return WhisperModelFolder(url: preferred, variant: preferredVariant)
        }
        if let fallback {
            return WhisperModelFolder(url: fallback, variant: fallbackVariant)
        }
        return nil
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
