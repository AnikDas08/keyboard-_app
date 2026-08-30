import Foundation

/// The Ananse Stroke Book writing model, ported from the web prototype
/// (`artifacts/ananse-keyboard/src/data/ananse.ts`). A letter is composed from a
/// family *head* plus a *stroke* (diacritic position).
///
/// This is the single source of truth for the iOS keyboard's layout and the
/// letters each key inserts. The on-screen glyphs are rendered with a bundled
/// Ananse font (one per glyph style) applied to the Latin letters.

enum FamilyId: String, CaseIterable {
    case vowel, bilabial, alveolar, velar
}

/// The available glyph designs, mirroring the web app's glyph catalog
/// (`src/data/glyphCatalog.ts`). "New" and "Classic" are the built-in designs;
/// the other six are family-agnostic sets traced from the user's drawings.
/// Each style is backed by its own bundled font (see `AnanseFont`).
enum GlyphStyle: String, CaseIterable {
    case new, classic, bow, fork, wave, cup, triangle, circle

    /// User-facing name shown on the style key.
    var displayName: String {
        switch self {
        case .new: return "New"
        case .classic: return "Classic"
        case .bow: return "Bow"
        case .fork: return "Fork"
        case .wave: return "Wave"
        case .cup: return "Cup"
        case .triangle: return "Triangle"
        case .circle: return "Circle"
        }
    }

    /// Bundled font resource (without `.ttf`) that draws this style.
    var fontResource: String {
        switch self {
        case .new: return "AnanseStrokeBookNew"
        case .classic: return "AnanseStrokeBook"
        case .bow: return "AnanseStrokeBookBow"
        case .fork: return "AnanseStrokeBookFork"
        case .wave: return "AnanseStrokeBookWave"
        case .cup: return "AnanseStrokeBookCup"
        case .triangle: return "AnanseStrokeBookTriangle"
        case .circle: return "AnanseStrokeBookCircle"
        }
    }

    /// The style after this one (wraps around) — used by the style cycle key.
    var next: GlyphStyle {
        let all = GlyphStyle.allCases
        let index = all.firstIndex(of: self) ?? 0
        return all[(index + 1) % all.count]
    }
}

enum Position: String {
    case shell, top, mid, root, rootXtra = "root-xtra", rootXtra2 = "root-xtra2"
}

struct AnanseFamily {
    let id: FamilyId
    let name: String
    let rootLetter: String
}

struct AnanseLetter {
    let english: String
    let family: FamilyId
    let position: Position
    let label: String
}

enum Ananse {
    /// Family display order for the keyboard's head row.
    static let familyOrder: [FamilyId] = [.vowel, .bilabial, .alveolar, .velar]

    /// Stroke order for the compose row. The `shell` is omitted because the
    /// head's own root letter lives on the head row (long-press a head to type it).
    static let strokeOrder: [Position] = [.top, .mid, .root, .rootXtra, .rootXtra2]

    static let families: [FamilyId: AnanseFamily] = [
        .vowel:    AnanseFamily(id: .vowel,    name: "A – Vowel Family",    rootLetter: "A"),
        .bilabial: AnanseFamily(id: .bilabial, name: "M – Bilabial Family", rootLetter: "M"),
        .alveolar: AnanseFamily(id: .alveolar, name: "N – Alveolar Family", rootLetter: "N"),
        .velar:    AnanseFamily(id: .velar,    name: "G – Velar Family",    rootLetter: "G"),
    ]

    /// Compact headings used above the family-grouped letter rows.
    static func familyShortName(_ family: FamilyId) -> String {
        switch family {
        case .vowel: return "VOWEL"
        case .bilabial: return "BILABIAL"
        case .alveolar: return "ALVEOLAR"
        case .velar: return "VELAR"
        }
    }

    static let letters: [AnanseLetter] = [
        // Vowel
        AnanseLetter(english: "A", family: .vowel, position: .shell, label: "Root/Shell"),
        AnanseLetter(english: "E", family: .vowel, position: .top, label: "Top"),
        AnanseLetter(english: "I", family: .vowel, position: .mid, label: "Mid"),
        AnanseLetter(english: "O", family: .vowel, position: .root, label: "Root"),
        AnanseLetter(english: "U", family: .vowel, position: .rootXtra, label: "Root Xtra"),
        // Bilabial
        AnanseLetter(english: "M", family: .bilabial, position: .shell, label: "Root/Shell"),
        AnanseLetter(english: "B", family: .bilabial, position: .top, label: "Top"),
        AnanseLetter(english: "P", family: .bilabial, position: .mid, label: "Mid"),
        AnanseLetter(english: "F", family: .bilabial, position: .root, label: "Root"),
        AnanseLetter(english: "W", family: .bilabial, position: .rootXtra, label: "Root Xtra"),
        // Alveolar
        AnanseLetter(english: "N", family: .alveolar, position: .shell, label: "Root/Shell"),
        AnanseLetter(english: "D", family: .alveolar, position: .top, label: "Top"),
        AnanseLetter(english: "T", family: .alveolar, position: .mid, label: "Mid"),
        AnanseLetter(english: "L", family: .alveolar, position: .root, label: "Root"),
        AnanseLetter(english: "R", family: .alveolar, position: .rootXtra, label: "Root Xtra"),
        AnanseLetter(english: "S", family: .alveolar, position: .rootXtra2, label: "Root Xtra"),
        // Velar
        AnanseLetter(english: "G", family: .velar, position: .shell, label: "Root/Shell"),
        AnanseLetter(english: "K", family: .velar, position: .top, label: "Top"),
        AnanseLetter(english: "H", family: .velar, position: .mid, label: "Mid"),
        AnanseLetter(english: "Y", family: .velar, position: .root, label: "Root"),
    ]

    /// Letters with no symbol of their own borrow the symbol(s) of the closest
    /// sound(s). The FIRST listed target is the one typed; C can borrow both S
    /// ("city") and K ("cat"). Mirrors `LETTER_EQUIVALENTS` in `ananse.ts`.
    static let equivalents: [String: [String]] = [
        "J": ["G"], "V": ["F"], "C": ["S", "K"], "X": ["S"], "Z": ["S"],
    ]

    /// Letters written as a sequence of symbols. Q is sounded "kw" → K + W.
    static let expansions: [String: [String]] = ["Q": ["K", "W"]]

    /// The standard QWERTY key order (rows of 10 / 9 / 7), mirroring the web
    /// keyboard's QWERTY layout. Every key shows the Ananse symbol(s) that
    /// write its letter; glyph-less letters resolve via `resolveLetters`.
    static let qwertyRows: [[String]] = [
        ["Q", "W", "E", "R", "T", "Y", "U", "I", "O", "P"],
        ["A", "S", "D", "F", "G", "H", "J", "K", "L"],
        ["Z", "X", "C", "V", "B", "N", "M"],
    ]

    /// Resolve a typed letter to the sequence of Ananse letters that write it.
    /// Most letters map to one letter; equivalents borrow their first target
    /// (C → S), expansions map to several (Q → K + W). Mirrors
    /// `resolveLetters` in `ananse.ts`.
    static func resolveLetters(_ english: String) -> [AnanseLetter] {
        let up = english.uppercased()
        if let expansion = expansions[up] {
            return expansion.compactMap { resolveLetter($0) }
        }
        if let single = resolveLetter(up) { return [single] }
        return []
    }

    /// Resolve one letter to its Ananse letter, following equivalents.
    static func resolveLetter(_ english: String) -> AnanseLetter? {
        let up = english.uppercased()
        if let direct = letters.first(where: { $0.english == up }) { return direct }
        if let target = equivalents[up]?.first {
            return letters.first { $0.english == target }
        }
        return nil
    }

    /// What a QWERTY key inserts: the resolved letters joined (C → "S",
    /// Q → "KW", most letters → themselves). Empty if unwritable.
    static func qwertyOutput(for english: String) -> String {
        resolveLetters(english).map { $0.english }.joined()
    }

    /// The letter produced by combining a family head with a stroke.
    static func letter(family: FamilyId, position: Position) -> AnanseLetter? {
        letters.first { $0.family == family && $0.position == position }
    }

    /// Canonical letters in stroke order for the family-grouped layout.
    static func letters(for family: FamilyId) -> [AnanseLetter] {
        let positions: [Position] = [.shell] + strokeOrder
        return positions.compactMap { letter(family: family, position: $0) }
    }

    /// The root/shell letter of a family (typed by long-pressing the head).
    static func rootLetter(of family: FamilyId) -> String {
        families[family]?.rootLetter ?? ""
    }

    /// Expand a letter to the actual text inserted into the document
    /// (e.g. "Q" → "KW"). Most letters insert themselves unchanged.
    static func textToInsert(for english: String) -> String {
        let up = english.uppercased()
        if let expansion = expansions[up] { return expansion.joined() }
        return up
    }

    /// Read an Ananse-convention Latin string back as plain English. Ananse
    /// stores capitals as lower-case (the font renders those bold) and normal
    /// letters as UPPER-case, so reading back inverts that mapping; everything
    /// else (spaces, punctuation, digits) passes through unchanged. Mirrors
    /// `artifacts/ananse-keyboard/src/lib/translit.ts` — keep the two in sync.
    static func ananseToEnglish(_ text: String) -> String {
        var out = ""
        for ch in text {
            if ch >= "a" && ch <= "z" { out.append(contentsOf: ch.uppercased()) }
            else if ch >= "A" && ch <= "Z" { out.append(contentsOf: ch.lowercased()) }
            else { out.append(ch) }
        }
        return out
    }
}
