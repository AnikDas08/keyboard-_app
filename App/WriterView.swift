import SwiftUI
import UIKit

struct WriterView: View {
    private static let draftKey = "ananse.text.v1"
    private static let manualMarksKey = "ananse.valueMarks.v1"

    @EnvironmentObject private var store: PrivateStore
    @StateObject private var keyboardState = InAppKeyboardState()
    @State private var draft = UserDefaults.standard.string(forKey: WriterView.draftKey) ?? ""
    @State private var manualAnnotations: [AnanseManualValueAnnotation] =
        (try? JSONDecoder().decode(
            [AnanseManualValueAnnotation].self,
            from: UserDefaults.standard.data(forKey: WriterView.manualMarksKey) ?? Data()
        )) ?? []
    @State private var isSharing = false
    @State private var shareItems: [Any] = []

    @State private var showAbout = false
    @State private var openPrivate = false
    @State private var showGenerate = false
    @State private var showValues = false
    @State private var showImageError = false
    @State private var imageErrorMessage = ""


    @State private var selectedRange: NSRange = NSRange(location: 0, length: 0)
    @State private var previousCursiveWeight: PreviewHangingLineWeight = .medium

    var targetDigitOffset: Int? {
        let utf16Text = draft as NSString
        let utf16Count = utf16Text.length
        func isDigit(at offset: Int) -> Bool {
            guard offset >= 0, offset < utf16Count else { return false }
            let codeUnit = utf16Text.character(at: offset)
            return codeUnit >= 48 && codeUnit <= 57
        }
        if selectedRange.length > 0 {
            let start = min(selectedRange.location, utf16Count)
            let end = min(selectedRange.location + selectedRange.length, utf16Count)
            if start < end {
                for offset in start..<end where isDigit(at: offset) {
                    return offset
                }
            }
        } else {
            let loc = selectedRange.location
            if isDigit(at: loc - 1) { return loc - 1 }
            if isDigit(at: loc) { return loc }
        }
        return nil
    }

    func toggleMark(offset: Int, kind: String) {
        manualAnnotations = AnanseValueNotation.toggled(manualAnnotations, at: offset, kind: kind, for: draft)
    }

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                Theme.appBackground.ignoresSafeArea()

                VStack(spacing: 12) {
                    topControls

                    canvasArea

                    predictionStrip
                }

                NavigationLink(destination: MessengerView().environmentObject(store), isActive: $openPrivate) {
                    EmptyView()
                }.hidden()
            }

            InAppKeyboardView(
                state: keyboardState,
                text: $draft,
                manualAnnotations: $manualAnnotations,
                selectedRange: $selectedRange,
                onReturn: {
                    let oldString = draft
                    guard let range = Range(selectedRange, in: draft) else { return }
                    draft.replaceSubrange(range, with: "\n")
                    selectedRange = NSRange(location: selectedRange.location + 1, length: 0)
                    manualAnnotations = AnanseValueNotation.transform(
                        manualAnnotations, from: oldString, to: draft
                    )
                }
            )
        }
        .navigationBarHidden(true)
        .onChange(of: draft) { newDraft in
            if newDraft.isEmpty {
                UserDefaults.standard.removeObject(forKey: WriterView.draftKey)
            } else {
                UserDefaults.standard.set(newDraft, forKey: WriterView.draftKey)
            }

            let clean = AnanseValueNotation.sanitize(manualAnnotations, for: newDraft)
            if clean != manualAnnotations {
                manualAnnotations = clean
            }
        }
        .onChange(of: manualAnnotations) { annotations in
            if let data = try? JSONEncoder().encode(annotations) {
                UserDefaults.standard.set(data, forKey: WriterView.manualMarksKey)
            }
        }
        .onAppear {
            keyboardState.restore()
            if keyboardState.hangingLine != .off {
                previousCursiveWeight = keyboardState.hangingLine
            }
            manualAnnotations = AnanseValueNotation.sanitize(
                manualAnnotations,
                for: draft
            )
            selectedRange = NSRange(location: draft.utf16.count, length: 0)
        }
        .sheet(isPresented: $isSharing) {
            WriterShareSheet(activityItems: shareItems)
        }
        .sheet(isPresented: $showAbout) {
            NavigationView {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Ananse Keyboard")
                            .font(.title2.bold())
                            .foregroundColor(Theme.appText)

                        Text("Ananse Stroke is a West African writing system. This app includes a writing space, a custom system keyboard, and a private messenger.")
                            .font(.body)

                        Text("Privacy & Apple Boundaries")
                            .font(.headline)
                            .padding(.top)

                        Text("The Ananse system keyboard does not request or require Full Access. Apple Messages and every receiving app control their own fonts; the keyboard cannot replace/read Apple Messages conversations or add Ananse E2E encryption to iMessage. Ananse keeps its private networking entirely outside the extension.")
                            .font(.body)
                            .foregroundColor(Theme.secondaryText)

                        Text("Private Messenger")
                            .font(.headline)
                            .padding(.top)

                        Text("Only this app's Private area supplies live E2E encrypted conversations. Messages can only be decrypted by the intended recipient. We cannot read your messages.")
                            .font(.body)
                            .foregroundColor(Theme.secondaryText)

                    }
                    .padding()
                }
                .navigationTitle("About")
                .navigationBarItems(trailing: Button("Done") { showAbout = false })
            }
        }
        .sheet(isPresented: $showValues) {
            NavigationView {
                Form {
                    Section {
                        Toggle("Automatic Values", isOn: $keyboardState.autoValues)
                            .onChange(of: keyboardState.autoValues) { _ in keyboardState.save() }
                            .tint(Theme.activeBlue)

                        Text("When automatic values are enabled, Ananse contextually places value marks (Tens, Hundreds, etc.) on numbers as you type.")
                            .font(.caption)
                            .foregroundColor(Theme.secondaryText)
                    }

                    if !keyboardState.autoValues {
                        Section(header: Text("Manual Marks")) {
                            if let offset = targetDigitOffset {
                                Text("Editing marks for digit at position \(offset)")
                                    .font(.caption)
                                    .foregroundColor(Theme.secondaryText)

                                HStack {
                                    Button("Top (Tens)") { toggleMark(offset: offset, kind: "top") }
                                    Spacer()
                                    Button("Mid (Hundreds)") { toggleMark(offset: offset, kind: "middle") }
                                }
                                .buttonStyle(.bordered)
                                .tint(Theme.activeBlue)

                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack {
                                        Button("Lower 1") { toggleMark(offset: offset, kind: "1") }
                                        Button("Lower 2") { toggleMark(offset: offset, kind: "2") }
                                        Button("Lower 3") { toggleMark(offset: offset, kind: "3") }
                                        Button("Lower 4") { toggleMark(offset: offset, kind: "4") }
                                        Button("Clear") { toggleMark(offset: offset, kind: "clear") }.tint(Theme.red)
                                    }
                                }
                                .buttonStyle(.bordered)
                                .tint(Theme.activeBlue)

                            } else {
                                Text("Place the cursor next to or select a digit to add value marks.")
                                    .foregroundColor(Theme.secondaryText)
                            }
                        }
                    }
                }
                .navigationTitle("Values")
                .navigationBarItems(trailing: Button("Done") { showValues = false })
            }
        }
        .alert(isPresented: $showImageError) {
            Alert(title: Text("Cannot Save Image"), message: Text(imageErrorMessage), dismissButton: .default(Text("OK")))
        }
        .sheet(isPresented: $showGenerate) {
            NavigationView {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        Text("Choose an Ananse character design to use in the keyboard:")
                            .font(.subheadline)
                            .foregroundColor(Theme.secondaryText)

                        let styles = PreviewGlyphStyle.allCases
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
                            ForEach(styles) { style in
                                Button(action: {
                                    keyboardState.style = style
                                    keyboardState.save()
                                }) {
                                    VStack {
                                        Text("A B C D E")
                                            .font(.ananse(size: 24, style: style))
                                            .foregroundColor(keyboardState.style == style ? .white : Theme.appText)
                                        Text(style.displayName)
                                            .font(.caption.bold())
                                            .foregroundColor(keyboardState.style == style ? .white : Theme.appText)
                                    }
                                    .padding()
                                    .frame(maxWidth: .infinity)
                                    .background(keyboardState.style == style ? Theme.activeBlue : Theme.white)
                                    .cornerRadius(12)
                                    .shadow(color: Color.black.opacity(0.05), radius: 2, y: 1)
                                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.lightBorder, lineWidth: 1))
                                }
                            }
                        }

                        Divider().padding(.vertical)

                        Text("Note: Custom head art uploaded on the website is tied to your browser and does not alter the installable font or sync to native apps.")
                            .font(.caption)
                            .foregroundColor(.gray)
                    }
                    .padding()
                }
                .navigationTitle("Character Designs")
                .navigationBarItems(trailing: Button("Done") { showGenerate = false })
            }
        }
    }

    private var topControls: some View {
        VStack(spacing: 12) {
            HStack {
                HStack(spacing: 0) {
                    Button("Print") {
                        keyboardState.hangingLine = .off
                        keyboardState.save()
                    }
                    .font(.system(size: 14, weight: .bold))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(keyboardState.hangingLine == .off ? Theme.activeBlue : Theme.white)
                    .foregroundColor(keyboardState.hangingLine == .off ? .white : Theme.secondaryText)

                    Button("‾ Cursive") {
                        if previousCursiveWeight == .off { previousCursiveWeight = .medium }
                        keyboardState.hangingLine = previousCursiveWeight
                        keyboardState.save()
                    }
                    .font(.system(size: 14, weight: .bold))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(keyboardState.hangingLine != .off ? Theme.activeBlue : Theme.white)
                    .foregroundColor(keyboardState.hangingLine != .off ? .white : Theme.secondaryText)
                }
                .cornerRadius(8)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.lightBorder, lineWidth: 1))
                .shadow(color: Color.black.opacity(0.05), radius: 2, y: 1)

                if keyboardState.hangingLine != .off {
                    HStack(spacing: 4) {
                        ForEach([PreviewHangingLineWeight.thin, .medium, .thick], id: \.self) { weight in
                            Button(action: {
                                keyboardState.hangingLine = weight
                                previousCursiveWeight = weight
                                keyboardState.save()
                            }) {
                                Rectangle()
                                    .fill(keyboardState.hangingLine == weight ? Theme.white : Theme.secondaryText)
                                    .frame(width: 16, height: weight == .thin ? 2 : (weight == .medium ? 4 : 6))
                                    .padding(8)
                                    .background(keyboardState.hangingLine == weight ? Theme.activeBlue : Theme.white)
                                    .cornerRadius(6)
                            }
                        }
                    }
                    .padding(.horizontal, 8)
                    .background(Theme.white)
                    .cornerRadius(8)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.lightBorder, lineWidth: 1))
                }

                Spacer()

                HStack(spacing: 8) {
                    ForEach([PreviewGlyphColor.red, .gold, .green, .black], id: \.self) { color in
                        Button(action: { keyboardState.glyphColor = color; keyboardState.save() }) {
                            Circle()
                                .fill(color.suColor)
                                .frame(width: 16, height: 16)
                                .overlay(
                                    Circle()
                                        .stroke(keyboardState.glyphColor == color ? Theme.activeBlue : Color.clear, lineWidth: 2)
                                        .padding(-3)
                                )
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Theme.white)
                .cornerRadius(8)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.lightBorder, lineWidth: 1))
                .shadow(color: Color.black.opacity(0.05), radius: 2, y: 1)
            }
            .padding(.horizontal, 12)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    actionButton(icon: "info.circle", title: "About") { showAbout = true }
                    actionButton(icon: "textformat.123", title: "Values") { showValues = true }
                    actionButton(icon: "lock.fill", title: "Private") { openPrivate = true }
                    actionButton(icon: "arrow.down.doc.fill", title: "Save\nas image", multiLine: true, disabled: draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) { saveAsImage() }
                    actionButton(icon: "link", title: "Share\nnote", multiLine: true, disabled: draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) { shareNote() }

                    Button(action: { showGenerate = true }) {
                        HStack(spacing: 6) {
                            Image(systemName: "pencil.and.outline")
                            Text("Customize\ncharacters")
                                .multilineTextAlignment(.center)
                        }
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 12)
                        .frame(height: 50)
                        .background(Theme.activeBlue)
                        .cornerRadius(8)
                        .shadow(color: Color.black.opacity(0.05), radius: 2, y: 1)
                    }
                }
                .padding(.horizontal, 12)
            }
        }
        .padding(.top, 8)
    }

    private func actionButton(icon: String, title: String, multiLine: Bool = false, disabled: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 14))
                if multiLine {
                    Text(title)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                } else {
                    Text(title)
                }
            }
            .font(.system(size: 12, weight: .bold))
            .foregroundColor(Theme.secondaryText)
            .padding(.horizontal, 12)
            .frame(height: 50)
            .background(Theme.white)
            .cornerRadius(8)
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.lightBorder, lineWidth: 1))
            .shadow(color: Color.black.opacity(0.05), radius: 2, y: 1)
        }
        .disabled(disabled)
        .opacity(disabled ? 0.5 : 1.0)
    }

    private var canvasArea: some View {
        ZStack(alignment: .topLeading) {
            Theme.white
                .cornerRadius(12)
                .shadow(color: Color.black.opacity(0.05), radius: 4, y: 2)

            if draft.isEmpty {
                Text("Type to see your Ananse text...")
                    .font(.system(size: 18, weight: .regular))
                    .foregroundColor(Theme.secondaryText.opacity(0.4))
                    .padding(16)
            }

            EditableAnanseCanvas(
                text: $draft,
                selectedRange: $selectedRange,
                automaticValues: keyboardState.autoValues,
                manualAnnotations: manualAnnotations,
                weightEm: keyboardState.hangingLine.emFactor,
                style: keyboardState.style,
                color: keyboardState.glyphColor,
                fontSize: keyboardState.script == .english ? 24 : 40,
                isEnglishMode: keyboardState.script == .english
            )
            .padding(8)
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 4)
    }

    private var predictionStrip: some View {
        HStack(spacing: 8) {
            let (startIdx, prefix) = PredictionEngine.currentWord(in: draft, before: selectedRange.location)
            let prev = PredictionEngine.previousWord(in: draft, before: selectedRange.location)
            let predictions = prefix.isEmpty ? PredictionEngine.predictNext(after: prev) : PredictionEngine.predict(prefix: prefix)

            ForEach(0..<3, id: \.self) { idx in
                if idx < predictions.count {
                    let word = predictions[idx]
                    Button(word) {
                        acceptPrediction(word: word, start: startIdx)
                    }
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(Theme.appText)
                    .frame(maxWidth: .infinity)
                    .frame(height: 36)
                    .background(Theme.white)
                    .cornerRadius(8)
                    .shadow(color: Color.black.opacity(0.05), radius: 1, x: 0, y: 1)
                } else {
                    Spacer().frame(maxWidth: .infinity)
                }
            }

            Button(action: {
                keyboardState.script = keyboardState.script == .ananse ? .english : .ananse
                keyboardState.save()
            }) {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.left.arrow.right")
                        .font(.system(size: 10))
                    Text(keyboardState.script == .ananse ? "Ananse" : "English")
                }
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(.white)
                .padding(.horizontal, 12)
                .frame(height: 36)
                .background(Theme.activeBlue)
                .cornerRadius(8)
            }

            Button(action: {
                keyboardState.slideEnabled.toggle()
                keyboardState.save()
            }) {
                HStack(spacing: 4) {
                    Text("~ Slide")
                }
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(keyboardState.slideEnabled ? .white : Theme.secondaryText)
                .padding(.horizontal, 12)
                .frame(height: 36)
                .background(keyboardState.slideEnabled ? Theme.activeBlue : Theme.white)
                .cornerRadius(8)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.lightBorder, lineWidth: 1))
            }
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
    }

    private func acceptPrediction(word: String, start: Int) {
        let oldString = draft
        let draftLength = draft.utf16.count
        let replacementLocation = selectedRange.length > 0
            ? selectedRange.location
            : start
        let replacementEnd = selectedRange.length > 0
            ? selectedRange.location + selectedRange.length
            : selectedRange.location
        guard replacementLocation <= replacementEnd,
              replacementEnd <= draftLength,
              let range = Range(
                NSRange(
                    location: replacementLocation,
                    length: replacementEnd - replacementLocation
                ),
                in: draft
              ) else { return }
        let newWord = word.uppercased() + " "
        draft.replaceSubrange(range, with: newWord)
        selectedRange = NSRange(
            location: replacementLocation + newWord.utf16.count,
            length: 0
        )

        manualAnnotations = AnanseValueNotation.transform(
            manualAnnotations,
            from: oldString,
            to: draft
        )
    }

    private func shareNote() {
        let text = """
        Read this Ananse note:
        \(draft)

        To see it written in Ananse, visit the app or website.
        """
        shareItems = [text]
        isSharing = true
    }

    private func saveAsImage() {
        let name = AnanseAppFont.register(resource: keyboardState.style.fontResource)
        guard let font = UIFont(name: name, size: 60), !font.familyName.contains("System") else {
            imageErrorMessage = "Could not load the Ananse font resource for this style."
            showImageError = true
            return
        }

        let view = HangingLineTextView()
        view.isEditable = false
        view.isSelectable = false
        view.isScrollEnabled = false
        view.backgroundColor = .white
        view.textContainerInset = UIEdgeInsets(top: 24, left: 24, bottom: 24, right: 24)

        view.font = font
        view.textColor = keyboardState.glyphColor.uiColor

        let values = keyboardState.autoValues
            ? AnanseValueNotation.automaticLayout(for: draft, enabled: true)
            : AnanseValueNotation.manualLayout(for: draft, annotations: manualAnnotations)

        view.attributedText = NSAttributedString(
            string: values.displayText,
            attributes: [
                .font: font,
                .foregroundColor: keyboardState.glyphColor.uiColor,
                .kern: -0.12 * font.pointSize,
            ]
        )
        view.hangingLineEm = keyboardState.hangingLine.emFactor
        view.valueMarks = values.marks
        view.refreshLines()

        // Initial layout to compute width, capped at 1200
        view.layoutManager.ensureLayout(for: view.textContainer)
        let used = view.layoutManager.usedRect(for: view.textContainer)
        let boundedWidth = min(max(400, used.width + 48), 1200)

        // Re-layout with finite width to allow wrapping
        view.frame = CGRect(x: 0, y: 0, width: boundedWidth, height: 100000)
        view.layoutManager.ensureLayout(for: view.textContainer)

        let finalUsed = view.layoutManager.usedRect(for: view.textContainer)
        let requiredHeight = finalUsed.height + 48

        if requiredHeight > 8000 {
            imageErrorMessage = "This draft is too long to safely generate as a single image. Please shorten it."
            showImageError = true
            return
        }

        let size = CGSize(width: boundedWidth, height: max(200, requiredHeight))

        view.frame = CGRect(origin: .zero, size: size)
        view.layoutIfNeeded()

        let renderer = UIGraphicsImageRenderer(size: size)
        let image = renderer.image { ctx in
            view.layer.render(in: ctx.cgContext)
        }

        shareItems = [image]
        isSharing = true
    }
}

private struct WriterShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(
            activityItems: activityItems,
            applicationActivities: nil
        )
    }

    func updateUIViewController(
        _ uiViewController: UIActivityViewController,
        context: Context
    ) {}
}

struct EditableAnanseCanvas: UIViewRepresentable {
    @Binding var text: String
    @Binding var selectedRange: NSRange
    let automaticValues: Bool
    let manualAnnotations: [AnanseManualValueAnnotation]
    let weightEm: CGFloat
    let style: PreviewGlyphStyle
    let color: PreviewGlyphColor
    var fontSize: CGFloat = 34
    var isEnglishMode: Bool = false

    func makeUIView(context: Context) -> EditableHangingLineTextView {
        let view = EditableHangingLineTextView()
        view.delegate = context.coordinator
        view.backgroundColor = .clear
        view.textColor = color.uiColor
        view.isScrollEnabled = true
        view.textContainerInset = UIEdgeInsets(top: 8, left: 0, bottom: 8, right: 0)
        view.textContainer.lineFragmentPadding = 0
        view.isEditable = true
        view.isSelectable = true
        return view
    }

    func updateUIView(_ view: EditableHangingLineTextView, context: Context) {
        let font: UIFont
        let attrString: String
        var marksToDraw: [AnanseValueMark] = []
        var lineEmToDraw: CGFloat = 0

        if isEnglishMode {
            font = .systemFont(ofSize: fontSize)
            attrString = Ananse.ananseToEnglish(text)
            marksToDraw = []
            lineEmToDraw = 0
        } else {
            let name = AnanseAppFont.register(resource: style.fontResource)
            font = UIFont(name: name, size: fontSize) ?? .systemFont(ofSize: fontSize)

            let values = automaticValues
                ? AnanseValueNotation.automaticEditableLayout(for: text, enabled: true)
                : AnanseValueNotation.manualLayout(for: text, annotations: manualAnnotations)
            attrString = values.displayText
            marksToDraw = values.marks
            lineEmToDraw = weightEm
        }

        let attr = NSMutableAttributedString(
            string: attrString,
            attributes: [
                .font: font,
                .foregroundColor: color.uiColor,
                .kern: isEnglishMode ? 0 : -0.12 * font.pointSize,
            ]
        )

        let currentRange = view.selectedRange
        let currentFont = view.attributedText.length > 0
            ? view.attributedText.attribute(.font, at: 0, effectiveRange: nil) as? UIFont
            : nil
        let currentColor = view.attributedText.length > 0
            ? view.attributedText.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? UIColor
            : nil
        let fontChanged = currentFont?.fontName != font.fontName
            || currentFont?.pointSize != font.pointSize
        if view.attributedText.string != attr.string
            || fontChanged
            || currentColor != color.uiColor {
            view.attributedText = attr
            if currentRange.location != NSNotFound && currentRange.location + currentRange.length <= attr.length {
                view.selectedRange = currentRange
            }
        }

        if view.selectedRange != selectedRange, selectedRange.location != NSNotFound, selectedRange.location + selectedRange.length <= attr.length {
            view.selectedRange = selectedRange
        }

        view.hangingLineEm = lineEmToDraw
        view.valueMarks = marksToDraw
        view.copiesCanonicalAsEnglish = !isEnglishMode
        view.refreshLines()
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    class Coordinator: NSObject, UITextViewDelegate {
        var parent: EditableAnanseCanvas
        init(_ parent: EditableAnanseCanvas) { self.parent = parent }
        func textViewDidChangeSelection(_ textView: UITextView) {
            DispatchQueue.main.async {
                if self.parent.selectedRange != textView.selectedRange {
                    self.parent.selectedRange = textView.selectedRange
                }
            }
        }
    }
}

final class EditableHangingLineTextView: HangingLineTextView {
    private let dummyInputView = UIView()
    var copiesCanonicalAsEnglish = true

    override var inputView: UIView? {
        get { dummyInputView }
        set { }
    }

    override func copy(_ sender: Any?) {
        guard let range = selectedTextRange,
              !range.isEmpty,
              let selected = text(in: range) else {
            return
        }
        UIPasteboard.general.string = copiesCanonicalAsEnglish
            ? Ananse.ananseToEnglish(selected)
            : selected
    }

    override func canPerformAction(_ action: Selector, withSender sender: Any?) -> Bool {
        if action == #selector(paste(_:)) || action == #selector(cut(_:)) {
            return false
        }
        return super.canPerformAction(action, withSender: sender)
    }

    override func caretRect(for position: UITextPosition) -> CGRect {
        var rect = super.caretRect(for: position)
        if rect.height > 0, let f = self.font { rect.size.height = f.lineHeight }
        return rect
    }
}

struct PredictionEngine {
    static let lexicon: [String] = [
        "the", "of", "and", "to", "a", "in", "for", "is", "on", "that",
        "by", "this", "with", "i", "you", "it", "not", "or", "be", "are",
        "from", "at", "as", "your", "all", "have", "new", "more", "an", "was",
        "we", "will", "home", "can", "us", "about", "if", "page", "my", "has",
        "search", "free", "but", "our", "one", "other", "do", "no", "information", "time",
        "they", "site", "he", "up", "may", "what", "which", "their", "news", "out",
        "use", "any", "there", "see", "only", "so", "his", "when", "contact", "here",
        "business", "who", "web", "also", "now", "help", "get", "pm", "view", "online",
        "first", "am", "been", "would", "how", "were", "me", "services", "some", "these",
        "spider", "weave", "woven", "ananse", "adinkra", "akan", "twi", "ghana", "kente", "proverb",
        "wisdom", "stroke", "glyph", "symbol", "keyboard", "goodbye", "afternoon"
    ]

    static let starters = ["the", "i", "you", "we", "what", "hello"]
    static let nextWordMap: [String: [String]] = [
        "the": ["spider", "story", "book", "world"],
        "i": ["am", "have", "want", "think"],
        "you": ["are", "can", "have", "know"],
        "we": ["are", "have", "can", "will"],
        "to": ["the", "be", "see", "have"],
        "a": ["good", "new", "story", "book"],
        "this": ["is", "one", "story"],
        "it": ["is", "was", "will"],
        "is": ["the", "a", "good", "great"],
        "hello": ["world", "friend", "there"],
        "thank": ["you"],
        "thanks": ["for", "you"],
        "please": ["help", "read", "write"],
        "good": ["morning", "night", "day"],
        "my": ["name", "friend", "family", "home"],
        "what": ["is", "do", "you"],
        "how": ["are", "do"],
        "spider": ["web", "story", "weave"]
    ]

    static func currentWord(in text: String, before cursor: Int) -> (start: Int, prefix: String) {
        let utf16 = Array(text.utf16)
        let end = min(cursor, utf16.count)
        var i = end
        while i > 0 {
            let ch = utf16[i - 1]
            if ch == 32 { break }
            let str = String(utf16CodeUnits: [ch], count: 1)
            if Ananse.resolveLetters(str).isEmpty && !str.allSatisfy({ $0.isNumber }) { break }
            i -= 1
        }
        let prefixUtf16 = Array(utf16[i..<end])
        return (i, String(utf16CodeUnits: prefixUtf16, count: prefixUtf16.count))
    }

    static func predict(prefix: String, limit: Int = 3) -> [String] {
        let p = prefix.lowercased()
        if p.isEmpty { return Array(lexicon.prefix(limit)) }
        let matches = lexicon.filter { $0.hasPrefix(p) && $0 != p }
        return Array(matches.prefix(limit))
    }

    static func previousWord(in text: String, before end: Int) -> String {
        let utf16 = Array(text.utf16)
        var i = min(end, utf16.count)
        while i > 0 && utf16[i - 1] == 32 { i -= 1 }
        let wordEnd = i
        while i > 0 && utf16[i - 1] != 32 { i -= 1 }
        let wordUtf16 = Array(utf16[i..<wordEnd])
        return String(utf16CodeUnits: wordUtf16, count: wordUtf16.count).lowercased()
    }

    static func predictNext(after prev: String, limit: Int = 3) -> [String] {
        let seed = prev.isEmpty ? starters : (nextWordMap[prev] ?? [])
        var out = seed
        for w in lexicon {
            if out.count >= limit { break }
            if w != prev && !out.contains(w) { out.append(w) }
        }
        return Array(out.prefix(limit))
    }
}
