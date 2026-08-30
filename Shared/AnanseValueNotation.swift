/// Pure value-stroke layout shared by the host preview and keyboard extension.
/// Text committed to another app is deliberately never changed: this model is
/// only for Ananse's contextual drawing layer.
struct AnanseValueMark: Equatable {
    let characterOffset: Int
    let top: Bool
    let middle: Bool
    let lower: Int
}

struct AnanseValueLayout: Equatable {
    let displayText: String
    let marks: [AnanseValueMark]
}
struct AnanseManualValueAnnotation: Codable, Equatable {
    var characterOffset: Int
    var top: Bool = false
    var middle: Bool = false
    var lower: Int = 0
    var isEmpty: Bool { !top && !middle && lower == 0 }
}

enum AnanseValueNotation {
    static let maximumWholeDigits = 15

    static func automaticLayout(for text: String, enabled: Bool) -> AnanseValueLayout {
        guard enabled else { return AnanseValueLayout(displayText: text, marks: []) }
        var output = "", marks: [AnanseValueMark] = []
        let chars = Array(text)
        var i = 0
        while i < chars.count {
            let start = i
            if chars[i] == "+" || chars[i] == "-" { i += 1 }
            let wholeStart = i
            while i < chars.count, chars[i].isNumber || chars[i] == "," { i += 1 }
            let wholeEnd = i
            if i < chars.count, chars[i] == "." {
                i += 1
                while i < chars.count, chars[i].isNumber { i += 1 }
            }
            let hasDigits = chars[wholeStart..<wholeEnd].contains { $0.isNumber }
            if !hasDigits {
                output.append(chars[start])
                i = start + 1
                continue
            }
            appendToken(Array(chars[start..<i]), to: &output, marks: &marks)
        }
        return AnanseValueLayout(displayText: output, marks: marks)
    }

    /// Computes automatic marks based on canonical offsets for the editable canvas,
    /// preserving the text 1:1 (without stripping zeros or commas).
    static func automaticEditableLayout(for text: String, enabled: Bool) -> AnanseValueLayout {
        guard enabled else { return AnanseValueLayout(displayText: text, marks: []) }
        var marks: [AnanseValueMark] = []
        let chars = Array(text)
        var i = 0
        var utf16Offset = 0

        while i < chars.count {
            let start = i
            let startOffset = utf16Offset

            if chars[i] == "+" || chars[i] == "-" {
                utf16Offset += String(chars[i]).utf16.count
                i += 1
            }
            let wholeStart = i
            while i < chars.count, chars[i].isNumber || chars[i] == "," {
                utf16Offset += String(chars[i]).utf16.count
                i += 1
            }
            let wholeEnd = i
            if i < chars.count, chars[i] == "." {
                utf16Offset += String(chars[i]).utf16.count
                i += 1
                while i < chars.count, chars[i].isNumber {
                    utf16Offset += String(chars[i]).utf16.count
                    i += 1
                }
            }
            let hasDigits = chars[wholeStart..<wholeEnd].contains { $0.isNumber }
            if !hasDigits {
                if i == start {
                    utf16Offset += String(chars[i]).utf16.count
                    i += 1
                }
                continue
            }
            let token = Array(chars[start..<i])
            let decimal = token.firstIndex(of: ".") ?? token.endIndex
            let wholePart = token[..<decimal]
            let digits = wholePart.filter { $0.isNumber }

            if digits.count <= maximumWholeDigits, !(digits.count > 1 && digits.first == "0"), !digits.allSatisfy({ $0 == "0" }) {
                var currentUtf16 = startOffset
                if token.first == "+" || token.first == "-" {
                    currentUtf16 += String(token[0]).utf16.count
                }
                var digitIndex = 0
                for ch in wholePart {
                    if ch.isNumber {
                        if ch != "0" {
                            let place = digits.count - digitIndex - 1
                            marks.append(AnanseValueMark(
                                characterOffset: currentUtf16,
                                top: place % 3 == 1,
                                middle: place % 3 == 2,
                                lower: lower(forPlace: place)
                            ))
                        }
                        digitIndex += 1
                    }
                    currentUtf16 += String(ch).utf16.count
                }
            }
        }
        return AnanseValueLayout(displayText: text, marks: marks)
    }

    static func manualLayout(for text: String, annotations: [AnanseManualValueAnnotation]) -> AnanseValueLayout {
        AnanseValueLayout(displayText: text, marks: sanitize(annotations, for: text).map {
            AnanseValueMark(characterOffset: $0.characterOffset, top: $0.top, middle: $0.middle, lower: $0.lower)
        })
    }

    static func sanitize(_ annotations: [AnanseManualValueAnnotation], for text: String) -> [AnanseManualValueAnnotation] {
        var byOffset: [Int: AnanseManualValueAnnotation] = [:]
        for var mark in annotations where mark.characterOffset >= 0 && mark.characterOffset < text.utf16.count {
            let index = String.Index(utf16Offset: mark.characterOffset, in: text)
            guard text[index].isNumber else { continue }
            mark.lower = normalizedLower(mark.lower)
            if !mark.isEmpty { byOffset[mark.characterOffset] = mark }
        }
        return byOffset.values.sorted { $0.characterOffset < $1.characterOffset }
    }

    /// Retain annotations on unchanged prefix/suffix characters across normal
    /// edits; edited/deleted digits lose their annotation instead of orphaning.
    static func transform(_ annotations: [AnanseManualValueAnnotation], from old: String, to new: String) -> [AnanseManualValueAnnotation] {
        let oldChars = Array(old), newChars = Array(new)
        var prefix = 0
        while prefix < min(oldChars.count, newChars.count), oldChars[prefix] == newChars[prefix] { prefix += 1 }
        var suffix = 0
        while suffix < oldChars.count - prefix, suffix < newChars.count - prefix,
              oldChars[oldChars.count - suffix - 1] == newChars[newChars.count - suffix - 1] { suffix += 1 }
        let delta = new.utf16.count - old.utf16.count
        let oldPrefixEnd = oldChars[..<prefix].map(String.init).joined().utf16.count
        let oldSuffixStart = old.utf16.count - oldChars.suffix(suffix).map(String.init).joined().utf16.count
        return sanitize(annotations.compactMap { mark in
            if mark.characterOffset < oldPrefixEnd { return mark }
            if mark.characterOffset >= oldSuffixStart {
                var shifted = mark; shifted.characterOffset += delta; return shifted
            }
            return nil
        }, for: new)
    }

    static func toggled(_ annotations: [AnanseManualValueAnnotation], at offset: Int, kind: String, for text: String) -> [AnanseManualValueAnnotation] {
        var marks = sanitize(annotations, for: text)
        var mark = marks.first { $0.characterOffset == offset } ?? AnanseManualValueAnnotation(characterOffset: offset)
        switch kind {
        case "top": mark.top = true
        case "middle": mark.middle = true
        case "clear": mark.top = false; mark.middle = false; mark.lower = 0
        default:
            let level = Int(kind) ?? 0
            mark.lower = level
        }
        marks.removeAll { $0.characterOffset == offset }
        if !mark.isEmpty { marks.append(mark) }
        return sanitize(marks, for: text)
    }

    private static func appendToken(
        _ token: [Character],
        to output: inout String,
        marks: inout [AnanseValueMark]
    ) {
        let decimal = token.firstIndex(of: ".") ?? token.endIndex
        let digits = token[..<decimal].filter { $0.isNumber }
        // IDs such as 0042 and out-of-range values must never hide data.
        guard digits.count <= maximumWholeDigits,
              !(digits.count > 1 && digits.first == "0") else {
            output.append(contentsOf: token)
            return
        }
        if token.first == "+" || token.first == "-" { output.append(token[0]) }
        if digits.allSatisfy({ $0 == "0" }) {
            output.append("0")
        } else {
            for (index, digit) in digits.enumerated() where digit != "0" {
                let place = digits.count - index - 1
                let offset = output.utf16.count
                output.append(digit)
                marks.append(AnanseValueMark(
                    characterOffset: offset,
                    top: place % 3 == 1,
                    middle: place % 3 == 2,
                    lower: lower(forPlace: place)
                ))
            }
        }
        if decimal != token.endIndex {
            output.append(".")
            output.append(contentsOf: token[(decimal + 1)...])
        }
    }

    private static func lower(forPlace place: Int) -> Int {
        if place >= 12 { return 4 }
        if place >= 9 { return 3 }
        if place >= 6 { return 2 }
        if place >= 3 { return 1 }
        return 0
    }

    /// Migrate drafts saved while the incorrect five/six-line controls were live.
    private static func normalizedLower(_ lower: Int) -> Int {
        switch lower {
        case 1, 2, 3, 4: return lower
        case 5: return 3
        case 6: return 4
        default: return 0
        }
    }
}