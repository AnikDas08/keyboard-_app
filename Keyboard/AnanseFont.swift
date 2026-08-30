import CoreText
import UIKit

/// Registers the bundled Ananse fonts (one .ttf per glyph style — see
/// `GlyphStyle`) so the keyboard can render Ananse glyphs by applying a font to
/// ordinary Latin letters. Returns the resolved PostScript name to use with
/// `UIFont(name:size:)`.
enum AnanseFont {
    private static var cachedNames: [String: String] = [:]
    private static var failedResources: Set<String> = []

    /// The font name for a glyph style, registering its .ttf on first use.
    /// Nil is intentional: callers must disclose a missing/broken resource
    /// rather than drawing Latin in the system font as if it were Ananse.
    static func fontName(for style: GlyphStyle) -> String? {
        register(resource: style.fontResource)
    }

    static func register(resource: String) -> String? {
        if let cached = cachedNames[resource] { return cached }
        if failedResources.contains(resource) { return nil }

        guard let url = Bundle.main.url(forResource: resource, withExtension: "ttf"),
              let data = try? Data(contentsOf: url),
              let provider = CGDataProvider(data: data as CFData),
              let cgFont = CGFont(provider),
              let name = cgFont.postScriptName as String? else {
            failedResources.insert(resource)
            return nil
        }

        CTFontManagerRegisterGraphicsFont(cgFont, nil) // ignore "already registered"
        cachedNames[resource] = name
        return name
    }
}
