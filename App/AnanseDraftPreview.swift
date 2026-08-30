import CoreText
import SwiftUI
import UIKit

/// Registers a bundled Ananse .ttf with CoreText and returns its PostScript
/// name for `UIFont(name:size:)`. Same approach as the keyboard extension's
/// AnanseFont, but self-contained: the extension's helper depends on
/// GlyphStyle, which only the Keyboard target compiles.
enum AnanseAppFont {
    private static var cachedNames: [String: String] = [:]

    static func register(resource: String) -> String {
        if let cached = cachedNames[resource] { return cached }

        guard let url = Bundle.main.url(forResource: resource, withExtension: "ttf"),
              let data = try? Data(contentsOf: url),
              let provider = CGDataProvider(data: data as CFData),
              let cgFont = CGFont(provider) else {
            cachedNames[resource] = "System"
            return "System"
        }

        CTFontManagerRegisterGraphicsFont(cgFont, nil) // ignore "already registered"
        let name = (cgFont.postScriptName as String?) ?? "System"
        cachedNames[resource] = name
        return name
    }
}

/// The Ananse Hanging Line weights offered by the host app's preview picker.
/// When the App Group (group.app.ananse.keyboard) is configured, the preview
/// follows the weight the keyboard extension saved to the shared suite; the
/// picker is the fallback for builds where the group isn't set up (mirroring
/// the web app, where the typing area has its own hanging-line control).
/// The em factors MUST match HANGING_LINE_WEIGHT_EM in the web app's
/// src/lib/preferences.ts and the keyboard's HangingLineWeight.
enum PreviewHangingLineWeight: String, CaseIterable, Identifiable {
    case off, thin, medium, thick

    var id: String { rawValue }

    /// Line thickness as a fraction of the glyph font size.
    var emFactor: CGFloat {
        switch self {
        case .off: return 0
        case .thin: return 0.042
        case .medium: return 0.084
        case .thick: return 0.126
        }
    }

    var displayName: String {
        switch self {
        case .off: return "Off"
        case .thin: return "Thin"
        case .medium: return "Medium"
        case .thick: return "Thick"
        }
    }
}

/// A read-only text view that renders the try-it draft in the bundled Ananse
/// font and draws the Ananse Hanging Line over each whole word: one continuous
/// line the glyph heads hang beneath, Devanagari-style, exactly like the web
/// keyboard's typing area. The line is CENTERED on the tops of the glyph heads
/// — 0.645em above the baseline, the same constant as the web's TypingArea CSS
/// and the keyboard's key overlay — so the head loops stay visible hanging
/// beneath it while top strokes still poke above.
class HangingLineTextView: UITextView {

    /// Line thickness as a fraction of the font size; 0 hides the lines.
    var hangingLineEm: CGFloat = 0 {
        didSet { overlay.setNeedsDisplay() }
    }
    /// Contextual value marks for the already-compacted display string. These
    /// are overlays, never characters or mutations of the numeral font.
    var valueMarks: [AnanseValueMark] = [] {
        didSet { overlay.setNeedsDisplay() }
    }

    /// Head-top level: glyph heads top out 0.645em above the baseline (from
    /// the font's design grid — see the web app's saveImage.ts for the math).
    private static let headTopLevelEm: CGFloat = 0.645

    /// Draws the word lines above the text. A subview of the text view (a
    /// scroll view), positioned in content coordinates so it scrolls with the
    /// draft.
    private final class OverlayView: UIView {
        weak var host: HangingLineTextView?
        override func draw(_ rect: CGRect) {
            host?.drawHangingLines()
        }
    }

    private let overlay = OverlayView()

    override var contentSize: CGSize {
        didSet {
            if !isScrollEnabled && oldValue != contentSize {
                invalidateIntrinsicContentSize()
            }
        }
    }

    override var intrinsicContentSize: CGSize {
        guard !isScrollEnabled else { return super.intrinsicContentSize }
        layoutManager.ensureLayout(for: textContainer)
        let used = layoutManager.usedRect(for: textContainer)
        return CGSize(
            width: UIView.noIntrinsicMetric,
            height: ceil(used.height + textContainerInset.top + textContainerInset.bottom)
        )
    }

    override init(frame: CGRect, textContainer: NSTextContainer?) {
        super.init(frame: frame, textContainer: textContainer)
        overlay.host = self
        overlay.backgroundColor = .clear
        overlay.isOpaque = false
        overlay.isUserInteractionEnabled = false
        addSubview(overlay)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// Call after the draft or weight changes so the lines follow the text.
    func refreshLines() {
        setNeedsLayout()
        overlay.setNeedsDisplay()
        if !isScrollEnabled {
            invalidateIntrinsicContentSize()
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        // Cover the whole scrollable content so lines on wrapped lines below
        // the fold are still drawn (and scroll with the text).
        let size = CGSize(
            width: max(contentSize.width, bounds.width),
            height: max(contentSize.height, bounds.height)
        )
        if overlay.frame.size != size {
            overlay.frame = CGRect(origin: .zero, size: size)
            overlay.setNeedsDisplay()
        }
        bringSubviewToFront(overlay)
    }

    private func drawHangingLines() {
        guard let font = font,
              let text = text, !text.isEmpty else { return }

        layoutManager.ensureLayout(for: textContainer)
        let thickness = hangingLineEm * font.pointSize
        let color = textColor ?? .label
        color.setFill()

        if hangingLineEm > 0 { for wordRange in HangingLineTextView.wordRanges(in: text) {
            let glyphRange = layoutManager.glyphRange(
                forCharacterRange: wordRange, actualCharacterRange: nil)
            guard glyphRange.length > 0 else { continue }

            // One line segment per line fragment the word touches (a word only
            // spans several fragments when it is longer than the view and has
            // to wrap mid-word).
            layoutManager.enumerateLineFragments(
                forGlyphRange: glyphRange
            ) { [self] fragmentRect, _, container, lineGlyphRange, _ in
                let segment = NSIntersectionRange(lineGlyphRange, glyphRange)
                guard segment.length > 0 else { return }
                let segmentRect = layoutManager.boundingRect(
                    forGlyphRange: segment, in: container)
                guard segmentRect.width > 0 else { return }

                // The glyph location's y is the baseline offset within the
                // line fragment; the line is centered on the head-top level
                // above that baseline.
                let baselineY = fragmentRect.minY
                    + layoutManager.location(forGlyphAt: segment.location).y
                let centerY = baselineY - HangingLineTextView.headTopLevelEm * font.pointSize
                let lineRect = CGRect(
                    x: segmentRect.minX + textContainerInset.left,
                    y: centerY - thickness / 2 + textContainerInset.top,
                    width: segmentRect.width,
                    height: thickness
                )
                UIBezierPath(roundedRect: lineRect, cornerRadius: 1).fill()
            }
        } }
        drawValueMarks(font: font, color: color)
    }

    private func drawValueMarks(font: UIFont, color: UIColor) {
        guard !valueMarks.isEmpty else { return }
        color.setFill()
        let thickness = max(1, font.pointSize * 0.055)
        func bodyRect(_ offset: Int) -> CGRect? {
            let range = NSRange(location: offset, length: 1)
            let glyphs = layoutManager.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
            guard glyphs.length > 0 else { return nil }
            return layoutManager.boundingRect(forGlyphRange: glyphs, in: textContainer)
                .offsetBy(dx: textContainerInset.left, dy: textContainerInset.top)
        }
        for mark in valueMarks {
            guard let rect = bodyRect(mark.characterOffset) else { continue }
            let baseline = rect.maxY - font.descender
            if mark.top {
                UIBezierPath(roundedRect: CGRect(x: rect.minX, y: rect.minY - thickness * 1.6,
                                                 width: rect.width, height: thickness),
                             cornerRadius: thickness / 2).fill()
            }
            if mark.middle {
                UIBezierPath(roundedRect: CGRect(x: rect.minX, y: baseline - font.pointSize * 0.35,
                                                 width: rect.width, height: thickness),
                             cornerRadius: thickness / 2).fill()
            }
        }
        // Lower lines deliberately use adjacent display offsets, so a line
        // reaches across a group only when every body reaches that line. A
        // four-lower mark therefore participates in lines 1 through 4,
        // rather than incorrectly drawing only its fourth line.
        for level in 1...4 {
            var run: [AnanseValueMark] = []
            for mark in valueMarks + [AnanseValueMark(characterOffset: -99, top: false, middle: false, lower: 0)] {
                if mark.lower >= level,
                   (run.isEmpty || (mark.characterOffset == run.last!.characterOffset + 1 &&
                    bodyRect(mark.characterOffset)?.minY == bodyRect(run.last!.characterOffset)?.minY)) {
                    run.append(mark)
                } else if !run.isEmpty {
                    if let first = bodyRect(run[0].characterOffset),
                       let last = bodyRect(run.last!.characterOffset) {
                        let y = first.maxY + CGFloat(level) * thickness * 1.8
                        UIBezierPath(roundedRect: CGRect(x: first.minX, y: y, width: last.maxX - first.minX, height: thickness),
                                     cornerRadius: thickness / 2).fill()
                    }
                    run = mark.lower >= level ? [mark] : []
                }
            }
        }
    }

    /// Split the draft into word ranges (UTF-16, for TextKit): a "word"
    /// character is any Unicode letter, combining mark, or number — the same
    /// rule as the web app's splitWords — and anything else (spaces,
    /// punctuation, emoji, line breaks) separates words.
    static func wordRanges(in text: String) -> [NSRange] {
        var ranges: [NSRange] = []
        var location = 0
        var wordStart: Int?
        for character in text {
            let isWord = character.unicodeScalars.first.map {
                CharacterSet.alphanumerics.contains($0)
            } ?? false
            if isWord {
                if wordStart == nil { wordStart = location }
            } else if let start = wordStart {
                ranges.append(NSRange(location: start, length: location - start))
                wordStart = nil
            }
            location += character.utf16.count
        }
        if let start = wordStart {
            ranges.append(NSRange(location: start, length: location - start))
        }
        return ranges
    }
}

/// The glyph ink colors the preview can render, keyed by the raw value the
/// keyboard extension saves ("AnanseKeyboard.glyphColor" in the App Group
/// suite). Mirrors GlyphColor in the Keyboard target and the web app's
/// GLYPH_COLOR_HEX palette (src/lib/preferences.ts) — red, gold, green, and
/// black, with black as the default ink; keep the RGB values in sync.
enum PreviewGlyphColor: String, CaseIterable, Identifiable {
    case red, gold, green, black

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .red: return "Red"
        case .gold: return "Gold"
        case .green: return "Green"
        case .black: return "Black"
        }
    }

    var uiColor: UIColor {
        switch self {
        case .red: return UIColor(red: 0xb9 / 255, green: 0x1c / 255, blue: 0x1c / 255, alpha: 1)
        case .gold: return UIColor(red: 0xb4 / 255, green: 0x53 / 255, blue: 0x09 / 255, alpha: 1)
        case .green: return UIColor(red: 0x15 / 255, green: 0x80 / 255, blue: 0x3d / 255, alpha: 1)
        case .black: return UIColor(red: 0x1f / 255, green: 0x29 / 255, blue: 0x37 / 255, alpha: 1)
        }
    }
}

/// The glyph designs the preview can render, keyed by the raw value the
/// keyboard extension saves ("AnanseKeyboard.glyphStyle" in the App Group
/// suite). Mirrors GlyphStyle in the Keyboard target, which the app target
/// does not compile; keep the cases and font resources in sync.
enum PreviewGlyphStyle: String, CaseIterable, Identifiable {
    case new, classic, bow, fork, wave, cup, triangle, circle

    var id: String { rawValue }

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
}

/// SwiftUI wrapper: a live Ananse-font preview of the try-it draft with the
/// per-word hanging line, mirroring the web keyboard's typing area. Renders
/// whatever glyph design the keyboard saved to the App Group suite (falling
/// back to "New", the keyboard's default, when the group isn't configured).
struct AnanseDraftPreview: UIViewRepresentable {
    let text: String
    let automaticValues: Bool
    let manualAnnotations: [AnanseManualValueAnnotation]
    let weightEm: CGFloat
    let style: PreviewGlyphStyle
    /// The glyph ink the keyboard saved (falls back to black, the web
    /// default, when the App Group isn't configured).
    let color: PreviewGlyphColor
    var isScrollEnabled: Bool = true
    var fontSize: CGFloat = 34

    func makeUIView(context: Context) -> HangingLineTextView {
        let view = HangingLineTextView()
        view.isEditable = false
        view.isSelectable = false
        view.isScrollEnabled = isScrollEnabled
        view.backgroundColor = .clear
        view.textColor = color.uiColor
        return view
    }

    func updateUIView(_ view: HangingLineTextView, context: Context) {
        // Resolve the font on every update so a style change made on the
        // keyboard shows the next time the preview refreshes.
        let name = AnanseAppFont.register(resource: style.fontResource)
        let font = UIFont(name: name, size: fontSize)
            ?? .systemFont(ofSize: fontSize)
        view.font = font
        view.isScrollEnabled = isScrollEnabled
        view.textColor = color.uiColor
        // Same tightened tracking as the web typing area (-0.12em).
        let values = automaticValues
            ? AnanseValueNotation.automaticLayout(for: text, enabled: true)
            : AnanseValueNotation.manualLayout(for: text, annotations: manualAnnotations)
        view.attributedText = NSAttributedString(
            string: values.displayText,
            attributes: [
                .font: font,
                .foregroundColor: color.uiColor,
                .kern: -0.12 * font.pointSize,
            ]
        )
        view.hangingLineEm = weightEm
        view.valueMarks = values.marks
        view.refreshLines()

        view.textContainerInset = isScrollEnabled ? UIEdgeInsets(top: 8, left: 0, bottom: 8, right: 0) : .zero
        view.textContainer.lineFragmentPadding = 0

        // Keep the end of the draft in view as it grows (the web area does
        // the same).
        if isScrollEnabled && view.contentSize.height > view.bounds.height {
            view.setContentOffset(
                CGPoint(x: 0, y: view.contentSize.height - view.bounds.height),
                animated: false
            )
        }
    }
}
