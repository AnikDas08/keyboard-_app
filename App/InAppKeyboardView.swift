import SwiftUI

class InAppKeyboardState: ObservableObject {
    enum AppKeyboardMode: String { case strokes, qwerty, families }
    enum OutputScript: String { case ananse, english }
    enum ShiftState { case off, on, caps }
    enum KeyboardLayer { case letters, symbols, emoji, reference }

    @Published var layoutMode: AppKeyboardMode = .families
    @Published var layer: KeyboardLayer = .letters
    @Published var style: PreviewGlyphStyle = .new
    @Published var hangingLine: PreviewHangingLineWeight = .off
    @Published var glyphColor: PreviewGlyphColor = .black
    @Published var autoValues: Bool = true
    @Published var script: OutputScript = .ananse
    @Published var shift: ShiftState = .off
    @Published var selectedFamily: FamilyId = .vowel
    @Published var slideEnabled: Bool = false

    private let group = UserDefaults(suiteName: "group.app.ananse.keyboard")

    init() { restore() }

    func restore() {
        // App Group migration and reading
        if let raw = group?.string(forKey: "AnanseKeyboard.layoutMode"), let m = AppKeyboardMode(rawValue: raw) {
            layoutMode = m
        } else if let raw = UserDefaults.standard.string(forKey: "InAppKeyboard.layoutMode"), let m = AppKeyboardMode(rawValue: raw) {
            layoutMode = m
            group?.set(raw, forKey: "AnanseKeyboard.layoutMode")
        }

        if let raw = group?.string(forKey: "AnanseKeyboard.outputScript"), let s = OutputScript(rawValue: raw) {
            script = s
        } else if let raw = UserDefaults.standard.string(forKey: "InAppKeyboard.script"), let s = OutputScript(rawValue: raw) {
            script = s
            group?.set(raw, forKey: "AnanseKeyboard.outputScript")
        }

        if let raw = group?.string(forKey: "AnanseKeyboard.glyphStyle"), let s = PreviewGlyphStyle(rawValue: raw) { style = s }
        if let raw = group?.string(forKey: "AnanseKeyboard.hangingLineWeight"), let h = PreviewHangingLineWeight(rawValue: raw) { hangingLine = h }
        if let raw = group?.string(forKey: "AnanseKeyboard.glyphColor"), let c = PreviewGlyphColor(rawValue: raw) { glyphColor = c }
        if let val = group?.object(forKey: "AnanseKeyboard.autoValues") as? Bool { autoValues = val }
        if let val = group?.object(forKey: "AnanseKeyboard.slideEnabled") as? Bool { slideEnabled = val }
    }

    func save() {
        // Save both shared and local fallback for compatibility
        group?.set(layoutMode.rawValue, forKey: "AnanseKeyboard.layoutMode")
        UserDefaults.standard.set(layoutMode.rawValue, forKey: "InAppKeyboard.layoutMode")

        group?.set(script.rawValue, forKey: "AnanseKeyboard.outputScript")
        UserDefaults.standard.set(script.rawValue, forKey: "InAppKeyboard.script")

        group?.set(style.rawValue, forKey: "AnanseKeyboard.glyphStyle")
        group?.set(hangingLine.rawValue, forKey: "AnanseKeyboard.hangingLineWeight")
        group?.set(glyphColor.rawValue, forKey: "AnanseKeyboard.glyphColor")
        group?.set(autoValues, forKey: "AnanseKeyboard.autoValues")
        group?.set(slideEnabled, forKey: "AnanseKeyboard.slideEnabled")
    }
}

struct KeyFrameData: Equatable {
    let englishLetter: String
    let bounds: CGRect
}

struct KeyFramePreferenceKey: PreferenceKey {
    static var defaultValue: [KeyFrameData] = []
    static func reduce(value: inout [KeyFrameData], nextValue: () -> [KeyFrameData]) {
        value.append(contentsOf: nextValue())
    }
}

struct InAppKeyboardView: View {
    @ObservedObject var state: InAppKeyboardState
    @Binding var text: String
    @Binding var manualAnnotations: [AnanseManualValueAnnotation]
    @Binding var selectedRange: NSRange
    @State private var keyFrames: [KeyFrameData] = []
    @State private var glidePath: [String] = []
    @State private var suppressLetterTap = false
    var onReturn: (() -> Void)? = nil

    private let symbolRows = [
        ["1", "2", "3", "4", "5", "6", "7", "8", "9", "0"],
        ["-", "/", ":", ";", "(", ")", "$", "&", "@", "\""],
        ["#", "%", "+", "=", ".", ",", "?", "!", "'", "*"]
    ]

    private let emojis = [
        "😀", "😁", "😂", "🤣", "😊", "😍", "😘", "😎",
        "🤔", "😴", "😭", "😡", "👍", "👎", "🙏", "👏",
        "🙌", "💪", "👋", "🤝", "❤️", "🧡", "💛", "💚",
        "💙", "💜", "🔥", "✨", "🎉", "🎊", "⭐", "🌟",
        "🌈", "☀️", "🌙", "⚡", "💧", "🌍", "🕷️", "🐍",
        "🦁", "🐘", "🌳", "🌸", "🍎", "☕", "⚽", "🎵"
    ]

    var body: some View {
        VStack(spacing: 6) {
            if state.layer == .symbols {
                symbolsLayout
            } else if state.layer == .emoji {
                emojiLayout
            } else if state.layer == .reference {
                referenceLayout
            } else {
                if state.layoutMode == .strokes {
                    strokesLayout
                } else if state.layoutMode == .qwerty {
                    qwertyLayout
                } else if state.layoutMode == .families {
                    familiesLayout
                }
            }

            utilityRow
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 8)
        .background(Theme.appBackground.edgesIgnoringSafeArea(.bottom))
        .coordinateSpace(name: "KeyboardSpace")
        .onPreferenceChange(KeyFramePreferenceKey.self) { self.keyFrames = $0 }
        .highPriorityGesture(
            DragGesture(minimumDistance: 5, coordinateSpace: .named("KeyboardSpace"))
                .onChanged { value in
                    guard state.slideEnabled, state.layer == .letters else { return }
                    if let frame = keyFrames.first(where: { $0.bounds.contains(value.location) }) {
                        suppressLetterTap = true
                        if glidePath.last != frame.englishLetter {
                            glidePath.append(frame.englishLetter)
                        }
                    }
                }
                .onEnded { _ in
                    guard state.slideEnabled, state.layer == .letters else {
                        glidePath.removeAll()
                        suppressLetterTap = false
                        return
                    }
                    if !glidePath.isEmpty {
                        insert(sequence: glidePath)
                    }
                    glidePath.removeAll()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                        suppressLetterTap = false
                    }
                }
        )
    }

    var symbolsLayout: some View {
        VStack(spacing: 4) {
            ForEach(0..<symbolRows.count, id: \.self) { ri in
                HStack(spacing: 4) {
                    ForEach(symbolRows[ri], id: \.self) { ch in
                        KeyView(
                            title: ch,
                            subtitle: ch.first?.isNumber == true ? ch : nil,
                            style: state.style,
                            color: state.glyphColor,
                            isSelected: false,
                            action: { insertDigit(ch) }
                        )
                    }
                }
                .frame(height: 48)
            }
        }
    }

    var emojiLayout: some View {
        ScrollView {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 8), spacing: 4) {
                ForEach(emojis, id: \.self) { e in
                    Button(action: { insertDigit(e) }) {
                        Text(e).font(.system(size: 24))
                            .frame(maxWidth: .infinity, minHeight: 40)
                            .background(Theme.white)
                            .cornerRadius(6)
                            .shadow(color: Color.black.opacity(0.05), radius: 1, x: 0, y: 1)
                    }
                }
            }
        }
        .frame(maxHeight: 160)
    }

    var referenceLayout: some View {
        VStack(spacing: 8) {
            Text("Shared Symbols").font(.caption).bold().foregroundColor(Theme.secondaryText)
            HStack(spacing: 4) {
                referenceKey(title: "C, Z, X = S", insert: "S")
                referenceKey(title: "J = G", insert: "G")
                referenceKey(title: "V = F", insert: "F")
            }
            HStack(spacing: 4) {
                referenceKey(title: "Q = K + W", insert: "KW")
            }
            Spacer()
        }
        .frame(maxHeight: 160)
        .padding(.vertical, 8)
    }

    func referenceKey(title: String, insert: String) -> some View {
        Button(action: { self.insert(englishLetter: insert) }) {
            ZStack {
                RoundedRectangle(cornerRadius: 6).fill(Theme.white).shadow(color: Color.black.opacity(0.05), radius: 1, x: 0, y: 1)
                Text(title).font(.system(size: 14, weight: .bold)).foregroundColor(Theme.appText)
            }
        }.frame(height: 44)
    }

    var strokesLayout: some View {
        VStack(spacing: 4) {
            HStack(spacing: 4) {
                ForEach(Ananse.familyOrder, id: \.self) { family in
                    HeadKeyView(family: family, state: state, onEmit: { insert(englishLetter: $0) })
                }
            }
            .frame(height: 48)

            HStack(spacing: 4) {
                ForEach(Ananse.strokeOrder, id: \.self) { position in
                    let letter = Ananse.letter(family: state.selectedFamily, position: position)
                    KeyView(
                        title: letter?.english ?? "",
                        subtitle: letter?.english,
                        style: state.style,
                        color: state.glyphColor,
                        isSelected: false,
                        disabled: letter == nil,
                        action: {
                            if let letter, !suppressLetterTap {
                                insert(englishLetter: letter.english)
                            }
                        },
                        glideLetter: letter?.english
                    )
                }
            }
            .frame(height: 48)
        }
    }

    var qwertyLayout: some View {
        VStack(spacing: 4) {
            ForEach(Ananse.qwertyRows, id: \.self) { row in
                HStack(spacing: 4) {
                    if row.count < 10 { Spacer(minLength: 0) }
                    ForEach(row, id: \.self) { letter in
                        KeyView(
                            title: Ananse.qwertyOutput(for: letter),
                            subtitle: letter,
                            style: state.style,
                            color: state.glyphColor,
                            isSelected: false,
                            action: {
                                if !suppressLetterTap {
                                    insert(englishLetter: letter)
                                }
                            },
                            glideLetter: letter
                        )
                    }
                    if row.count < 10 { Spacer(minLength: 0) }
                }
                .frame(height: 48)
            }
        }
    }

    var familiesLayout: some View {
        VStack(spacing: 4) {
            ForEach(Ananse.familyOrder, id: \.self) { family in
                VStack(alignment: .leading, spacing: 2) {
                    Text(Ananse.familyShortName(family))
                        .font(.system(size: 8, weight: .bold))
                        .foregroundColor(Theme.secondaryText)
                    HStack(spacing: 4) {
                        ForEach(Ananse.letters.filter { $0.family == family }, id: \.english) { letter in
                            KeyView(
                                title: Ananse.textToInsert(for: letter.english),
                                subtitle: letter.english,
                                style: state.style,
                                color: state.glyphColor,
                                isSelected: false,
                                action: {
                                    if !suppressLetterTap {
                                        insert(englishLetter: letter.english)
                                    }
                                },
                                glideLetter: letter.english
                            )
                        }
                    }
                }
                .frame(height: 58)
            }
        }
    }

    var utilityRow: some View {
        HStack(spacing: 4) {
            UtilityButton(title: state.shift == .caps ? "⇪" : "⇧", isActive: state.shift != .off, action: {
                switch state.shift {
                case .off: state.shift = .on
                case .on: state.shift = .caps
                case .caps: state.shift = .off
                }
            })

            UtilityButton(title: state.layer == .symbols ? "ABC" : "123", action: {
                state.layer = state.layer == .symbols ? .letters : .symbols
            })

            UtilityButton(title: state.layer == .emoji ? "ABC" : "😀", action: {
                state.layer = state.layer == .emoji ? .letters : .emoji
            })

            UtilityButton(icon: "square.grid.2x2.fill", isActive: state.layer == .reference, action: {
                if state.layer == .reference {
                    state.layer = .letters
                } else {
                    state.layer = .reference
                }
            })

            UtilityButton(title: "Aa", action: {
                switch state.layoutMode {
                case .strokes: state.layoutMode = .qwerty
                case .qwerty: state.layoutMode = .families
                case .families: state.layoutMode = .strokes
                }
                state.save()
            })

            UtilityButton(title: "space", width: .infinity, action: { insertDigit(" ") })

            UtilityButton(icon: "return", backgroundColor: Theme.activeBlue, foregroundColor: .white, action: {
                if let onReturn = onReturn { onReturn() } else { insertDigit("\n") }
            })

            UtilityButton(icon: "delete.left.fill", action: {
                deleteBackward()
            })
        }
        .frame(height: 44)
    }

    func replaceSelection(with newText: String) {
        let oldString = text
        guard let range = Range(selectedRange, in: text) else { return }

        text.replaceSubrange(range, with: newText)

        selectedRange = NSRange(location: selectedRange.location + newText.utf16.count, length: 0)

        manualAnnotations = AnanseValueNotation.transform(
            manualAnnotations,
            from: oldString,
            to: text
        )
    }

    func deleteBackward() {
        if selectedRange.length > 0 {
            replaceSelection(with: "")
        } else if selectedRange.location > 0 {
            let oldString = text
            let endIndex = text.utf16.index(text.utf16.startIndex, offsetBy: selectedRange.location)
            if let stringEndIndex = String.Index(endIndex, within: text) {
                let startIndex = text.index(before: stringEndIndex)
                text.removeSubrange(startIndex..<stringEndIndex)
                let removedUTF16Length = oldString[startIndex..<stringEndIndex].utf16.count
                selectedRange = NSRange(location: selectedRange.location - removedUTF16Length, length: 0)

                manualAnnotations = AnanseValueNotation.transform(
                    manualAnnotations,
                    from: oldString,
                    to: text
                )
            }
        }
    }

    func insert(sequence: [String]) {
        var combined = ""
        var currentShift = state.shift

        for letter in sequence {
            let resolved = Ananse.textToInsert(for: letter)
            let isCapital = (currentShift != .off)
            combined += isCapital ? resolved.lowercased() : resolved.uppercased()
            if currentShift == .on {
                currentShift = .off
            }
        }

        replaceSelection(with: combined)
        if state.shift == .on { state.shift = .off }
    }

    func insert(englishLetter: String) {
        let resolved = Ananse.textToInsert(for: englishLetter)
        let isCapital = (state.shift != .off)
        let canonicalText = isCapital ? resolved.lowercased() : resolved.uppercased()
        replaceSelection(with: canonicalText)

        if state.shift == .on {
            state.shift = .off
        }
    }

    func insertDigit(_ digit: String) {
        replaceSelection(with: digit)
    }
}

struct KeyView: View {
    let title: String
    let subtitle: String?
    let style: PreviewGlyphStyle
    let color: PreviewGlyphColor
    let isSelected: Bool
    var disabled: Bool = false
    let action: () -> Void
    var width: CGFloat? = nil
    var glideLetter: String? = nil

    var body: some View {
        Button(action: action) {
            ZStack {
                RoundedRectangle(cornerRadius: 6)
                    .fill(disabled ? Color.gray.opacity(0.1) : (isSelected ? Theme.activeBlue : Theme.white))
                    .shadow(color: Color.black.opacity(0.05), radius: 1, x: 0, y: 1)

                VStack(spacing: 2) {
                    Text(title)
                        .font(subtitle != nil ? .ananse(size: 22, style: style) : .system(size: 18, weight: .medium))
                        .foregroundColor(disabled ? .gray : (isSelected ? .white : color.suColor))

                    if let sub = subtitle {
                        Text(sub)
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(disabled ? .gray : (isSelected ? .white : Theme.appText))
                    }
                }
            }
        }
        .disabled(disabled)
        .frame(maxWidth: width ?? .infinity, maxHeight: .infinity)
        .background(
            GeometryReader { geo in
                Color.clear.preference(
                    key: KeyFramePreferenceKey.self,
                    value: glideLetter != nil ? [KeyFrameData(englishLetter: glideLetter!, bounds: geo.frame(in: .named("KeyboardSpace")))] : []
                )
            }
        )
    }
}

struct HeadKeyView: View {
    let family: FamilyId
    @ObservedObject var state: InAppKeyboardState
    let onEmit: (String) -> Void

    @State private var lastTap: Date?

    var body: some View {
        let isSelected = state.selectedFamily == family
        let root = Ananse.rootLetter(of: family)

        Button(action: {
            let now = Date()
            if let last = lastTap, now.timeIntervalSince(last) < 0.4 {
                onEmit(root)
                lastTap = nil
            } else {
                state.selectedFamily = family
                lastTap = now
            }
        }) {
            ZStack {
                RoundedRectangle(cornerRadius: 6)
                    .fill(isSelected ? Theme.activeBlue : Theme.white)
                    .shadow(color: Color.black.opacity(0.05), radius: 1, x: 0, y: 1)

                Text(root)
                    .font(.ananse(size: 22, style: state.style))
                    .foregroundColor(isSelected ? .white : state.glyphColor.suColor)
            }
        }
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 0.4).onEnded { _ in
                onEmit(root)
            }
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct UtilityButton: View {
    var title: String? = nil
    var icon: String? = nil
    var isActive: Bool = false
    var backgroundColor: Color? = nil
    var foregroundColor: Color? = nil
    var width: CGFloat? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                RoundedRectangle(cornerRadius: 6)
                    .fill(isActive ? Theme.activeBlue : (backgroundColor ?? Color(red: 0.88, green: 0.90, blue: 0.93)))

                if let icon = icon {
                    Image(systemName: icon)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(isActive ? .white : (foregroundColor ?? Theme.appText))
                } else if let title = title {
                    Text(title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(isActive ? .white : (foregroundColor ?? Theme.appText))
                        .minimumScaleFactor(0.6)
                        .lineLimit(1)
                        .padding(.horizontal, 4)
                }
            }
        }
        .frame(maxWidth: width ?? .infinity, maxHeight: .infinity)
    }
}
