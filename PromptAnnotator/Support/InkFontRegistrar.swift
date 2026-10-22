import AppKit
import CoreText
import Foundation
import os.log

/// Registers bundled Departure Mono (and any other .otf/.ttf) at launch.
/// ATSApplicationFontsPath=Fonts is still set; this covers flattened or late copies.
enum InkFontRegistrar {
    private static let log = Logger(subsystem: "com.bicrick.PromptAnnotator", category: "fonts")
    private static var didRun = false

    /// Call once from `applicationDidFinishLaunching` before any SwiftUI chrome paints.
    @MainActor
    static func registerBundledFonts() {
        guard !didRun else { return }
        didRun = true

        let urls = discoverFontURLs()
        if urls.isEmpty {
            log.error("da transcribuh: no .otf/.ttf found in bundle Resources (looked for Fonts/ and root)")
            NSLog("da transcribuh: no .otf/.ttf found in bundle Resources")
        }

        for url in urls {
            var error: Unmanaged<CFError>?
            let ok = CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error)
            if ok {
                log.info("registered font \(url.lastPathComponent, privacy: .public)")
                NSLog("da transcribuh: registered font %@", url.lastPathComponent)
            } else {
                let detail = error?.takeRetainedValue().localizedDescription ?? "unknown"
                log.error("font register failed \(url.lastPathComponent, privacy: .public): \(detail, privacy: .public)")
                NSLog("da transcribuh: font register failed %@: %@", url.lastPathComponent, detail)
            }
        }

        verifyDepartureMono()
    }

    /// PostScript / family names we accept for chrome.
    static let candidateNames = [
        "DepartureMono-Regular", // nameID 6 (PostScript) — preferred
        "Departure Mono",        // nameID 1 / 16 (family)
        "Departure Mono Regular",
    ]

    static func resolveNSFont(size: CGFloat) -> NSFont {
        for name in candidateNames {
            if let font = NSFont(name: name, size: size) {
                return upright(font)
            }
        }
        return upright(NSFont.monospacedSystemFont(ofSize: size, weight: .regular))
    }

    /// Strip italic/oblique traits — Departure Mono has no italic; never synthesize slant.
    /// AppKit `withSymbolicTraits` returns a non-optional `NSFontDescriptor` (unlike UIKit).
    static func upright(_ font: NSFont) -> NSFont {
        var traits = font.fontDescriptor.symbolicTraits
        guard traits.contains(.italic) else { return font }
        traits.remove(.italic)
        // macOS: non-optional. Do not `guard let` — that only compiles against UIKit.
        let descriptor = font.fontDescriptor.withSymbolicTraits(traits)
        return NSFont(descriptor: descriptor, size: font.pointSize) ?? font
    }

    static var isDepartureAvailable: Bool {
        candidateNames.contains { NSFont(name: $0, size: 12) != nil }
    }

    private static func verifyDepartureMono() {
        if isDepartureAvailable {
            let hit = candidateNames.first { NSFont(name: $0, size: 12) != nil } ?? "?"
            log.info("Departure Mono available as \(hit, privacy: .public)")
            NSLog("da transcribuh: Departure Mono available as %@", hit)
        } else {
            log.error("Departure Mono NOT available after registration — chrome will use system monospaced")
            NSLog("da transcribuh: Departure Mono NOT available after registration — using system monospaced fallback")
            let available = NSFontManager.shared.availableFonts.filter {
                $0.localizedCaseInsensitiveContains("departure") || $0.localizedCaseInsensitiveContains("mono")
            }
            NSLog("da transcribuh: related fonts: %@", available.joined(separator: ", "))
        }
    }

    private static func discoverFontURLs() -> [URL] {
        var found: [URL] = []
        let bundle = Bundle.main
        let exts = ["otf", "ttf", "ttc"]

        for ext in exts {
            if let urls = bundle.urls(forResourcesWithExtension: ext, subdirectory: "Fonts") {
                found.append(contentsOf: urls)
            }
            if let urls = bundle.urls(forResourcesWithExtension: ext, subdirectory: nil) {
                found.append(contentsOf: urls)
            }
        }

        if let root = bundle.resourceURL {
            found.append(contentsOf: fonts(in: root.appendingPathComponent("Fonts", isDirectory: true)))
            found.append(contentsOf: fonts(in: root))
        }

        // Unique by path
        var seen = Set<String>()
        return found.filter { url in
            let path = url.path
            guard !seen.contains(path) else { return false }
            guard FileManager.default.fileExists(atPath: path) else { return false }
            let ext = url.pathExtension.lowercased()
            guard exts.contains(ext) else { return false }
            seen.insert(path)
            return true
        }
    }

    private static func fonts(in directory: URL) -> [URL] {
        guard let kids = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else { return [] }
        return kids.filter { ["otf", "ttf", "ttc"].contains($0.pathExtension.lowercased()) }
    }
}
