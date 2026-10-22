import AppKit
import CoreText

/// Fonts that are safe to put in AppKit / Core Text attributes dictionaries.
///
/// Some `NSFont` factory APIs are annotated nonnull but can still yield a nil
/// ObjC reference (notably monospaced system fonts under certain cascade /
/// weight combinations). Bridging that into `[.font: font]` throws
/// `NSInvalidArgumentException` from `NSDictionary`.
enum FontMetrics {
    private struct Key: Hashable {
        var size: CGFloat
        var weight: CGFloat
        var mono: Bool
    }

    private static var cache: [Key: NSFont] = [:]

    /// Width of `text` for island / caption layout. Never passes a nil font into AppKit.
    static func width(of text: String, size: CGFloat, weight: NSFont.Weight, mono: Bool) -> CGFloat {
        let font = font(size: size, weight: weight, mono: mono)
        return (text as NSString).size(withAttributes: [.font: font]).width
    }

    /// Cached measuring / drawing font. Guaranteed non-nil for dictionary attributes.
    static func font(size: CGFloat, weight: NSFont.Weight = .regular, mono: Bool = false) -> NSFont {
        let key = Key(size: size, weight: weight.rawValue, mono: mono)
        if let hit = cache[key] { return hit }
        let resolved = resolve(size: size, weight: weight, mono: mono)
        cache[key] = resolved
        return resolved
    }

    private static func resolve(size: CGFloat, weight: NSFont.Weight, mono: Bool) -> NSFont {
        // Prefer NSFont factories when they produce a usable instance — they honor weight.
        if let preferred = preferredNSFont(size: size, weight: weight, mono: mono) {
            return preferred
        }
        // CTFont UI fonts are truly optional and never a secret nil reference.
        // Use `.system` only — mono was already attempted via NSFont factories above.
        if let ct = CTFontCreateUIFontForLanguage(.system, size, nil) {
            return ct as NSFont
        }
        if let user = NSFont.userFont(ofSize: size) {
            return user
        }
        // Helvetica ships with macOS; CreateWithName does not return NULL for it.
        return CTFontCreateWithName("Helvetica" as CFString, size, nil) as NSFont
    }

    private static func preferredNSFont(size: CGFloat, weight: NSFont.Weight, mono: Bool) -> NSFont? {
        // Digit mono matches SwiftUI `.monospacedDigit()` / clock metrics and is more
        // reliable than `monospacedSystemFont` when a full monospaced face is missing.
        let candidates: [NSFont]
        if mono {
            var list: [NSFont] = []
            // Prefer bundled Departure Mono (same face as Ink chrome) when registered.
            for name in InkFontRegistrar.candidateNames {
                if let font = NSFont(name: name, size: size) {
                    list.append(font)
                }
            }
            list.append(contentsOf: [
                NSFont.monospacedDigitSystemFont(ofSize: size, weight: weight),
                NSFont.monospacedSystemFont(ofSize: size, weight: weight),
            ])
            candidates = list
        } else {
            candidates = [
                NSFont.systemFont(ofSize: size, weight: weight),
                NSFont.systemFont(ofSize: size),
            ]
        }
        for candidate in candidates {
            if let usable = usable(candidate) {
                return mono ? InkFontRegistrar.upright(usable) : usable
            }
        }
        return nil
    }

    /// Rejects secretly-nil ObjC refs and empty font names before attributes bridging.
    private static func usable(_ font: NSFont) -> NSFont? {
        let boxed: Any = font
        guard let object = boxed as? NSFont else { return nil }
        guard object.pointSize > 0 else { return nil }
        let name = object.fontName
        guard !name.isEmpty else { return nil }
        return object
    }
}
