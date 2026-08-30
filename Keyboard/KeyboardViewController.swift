import UIKit

/// A key that can draw the Ananse Hanging Line over its glyph label: one
/// continuous line the glyph heads hang beneath, Devanagari-style, mirroring
/// the web keyboard's typing-area option. The line is CENTERED on the tops of
/// the glyph heads — 0.645em above the baseline, same constant as the web's
/// TypingArea CSS and PNG export — so the head loops stay visible hanging
/// beneath it while top strokes still poke above.
final class KeyButton: UIButton {

    /// Line thickness as a fraction of the glyph font size (an "em" factor,
    /// from `HangingLineWeight.emFactor`). 0 hides the line.
    var hangingLineEm: CGFloat = 0 { didSet { setNeedsLayout() } }
    /// The font drawing the Ananse glyph run (differs from `titleLabel!.font`
    /// on QWERTY keys, whose attributed title mixes glyph and Latin fonts).
    var glyphFont: UIFont? { didSet { setNeedsLayout() } }
    /// The glyph run the line should span (the first, Ananse-drawn line of the
    /// title). Empty hides the line (e.g. blank stroke keys).
    var glyphText: String = "" { didSet { setNeedsLayout() } }

    /// Head-top level: glyph heads top out 0.645em above the baseline (from
    /// the font's design grid — see the web app's saveImage.ts for the math).
    private static let headTopLevelEm: CGFloat = 0.645

    private let lineView = UIView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        lineView.isUserInteractionEnabled = false
        lineView.isHidden = true
        lineView.layer.cornerRadius = 1
        addSubview(lineView)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard hangingLineEm > 0, !glyphText.isEmpty, isEnabled,
              let label = titleLabel, let font = glyphFont else {
            lineView.isHidden = true
            return
        }
        // The first title line's baseline sits one ascender below the label
        // top; the line is centered on the head-top level above it.
        let em = font.pointSize
        let thickness = hangingLineEm * em
        let baselineY = label.frame.minY + font.ascender
        let centerY = baselineY - KeyButton.headTopLevelEm * em
        let width = (glyphText as NSString)
            .size(withAttributes: [.font: font]).width
        lineView.frame = CGRect(
            x: label.frame.midX - width / 2,
            y: centerY - thickness / 2,
            width: width,
            height: thickness
        )
        lineView.backgroundColor = currentTitleColor
        lineView.isHidden = false
        bringSubviewToFront(lineView)
    }
}

/// The iOS custom keyboard. Builds its layout programmatically and inserts
/// composed letters into the host app via `textDocumentProxy`.
///
/// Three layouts, cycled by the utility-row layout key (mirrors the web app):
///   • Families (canonical letters grouped into four compact family rows)
///   • Strokes (head + stroke compose board)
///       – Tap a family head  → select that family (the stroke row composes from it)
///       – Double-tap or long-press a head → type the family's root/shell letter
///       – Tap a stroke       → type the composed letter
///   • QWERTY (standard 10/9/7 key order, Ananse symbols on every key)
///       – Tap a key → type its letter; glyph-less letters borrow the closest
///         sound's symbol (C types S) and Q types the expansion KW.
///
/// The style key cycles the glyph design used to draw the keys — New, Classic,
/// plus the six designs traced from the user's drawings (Bow, Fork, Wave, Cup,
/// Triangle, Circle). Each style is a bundled font (see `GlyphStyle`).
final class KeyboardViewController: UIInputViewController {

    /// Families is the fresh-install default; the cycle follows the approved
    /// keyboard order: Families → QWERTY → Strokes.
    private enum LayoutMode: String {
        case families, qwerty, strokes

        var next: LayoutMode {
            switch self {
            case .families: return .qwerty
            case .qwerty: return .strokes
            case .strokes: return .families
            }
        }

        var displayName: String {
            switch self {
            case .families: return "Families"
            case .qwerty: return "QWERTY"
            case .strokes: return "Strokes"
            }
        }
    }
    private var layoutMode: LayoutMode = .families

    /// The glyph design drawing the keys; cycled by the style key.
    private var style: GlyphStyle = .new

    /// The Ananse Hanging Line drawn over the key glyphs: off, or one of the
    /// three weights shared with the web keyboard. The em factors MUST match
    /// HANGING_LINE_WEIGHT_EM in the web app's src/lib/preferences.ts so a
    /// weight dialled in on the web looks the same on the phone.
    private enum HangingLineWeight: String, CaseIterable {
        case off, thin, medium, thick

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

        var next: HangingLineWeight {
            let all = HangingLineWeight.allCases
            return all[(all.firstIndex(of: self)! + 1) % all.count]
        }
    }

    private var hangingLine: HangingLineWeight = .off

    /// Glyph ink color for the key glyphs, mirroring the web app's curated
    /// palette (GLYPH_COLOR_HEX in src/lib/preferences.ts): red, gold, green,
    /// and black, with black as the default ink.
    /// The RGB values MUST match the web's so a color dialled in anywhere
    /// looks the same.
    private enum GlyphColor: String, CaseIterable {
        case red, gold, green, black

        var uiColor: UIColor {
            switch self {
            case .red: return UIColor(red: 0xb9 / 255, green: 0x1c / 255, blue: 0x1c / 255, alpha: 1)
            case .gold: return UIColor(red: 0xb4 / 255, green: 0x53 / 255, blue: 0x09 / 255, alpha: 1)
            case .green: return UIColor(red: 0x15 / 255, green: 0x80 / 255, blue: 0x3d / 255, alpha: 1)
            case .black: return UIColor(red: 0x1f / 255, green: 0x29 / 255, blue: 0x37 / 255, alpha: 1)
            }
        }

        var displayName: String {
            switch self {
            case .red: return "Red"
            case .gold: return "Gold"
            case .green: return "Green"
            case .black: return "Black"
            }
        }

        var next: GlyphColor {
            let all = GlyphColor.allCases
            return all[(all.firstIndex(of: self)! + 1) % all.count]
        }
    }

    private var glyphColor: GlyphColor = .black

    /// App Group shared with the host app so its try-it preview can mirror
    /// the glyph style and hanging-line weight dialled in here. MUST match
    /// the group in project.yml and ContentView.swift. Registered under the
    /// developer's own team — when the group isn't configured (or the ID was
    /// changed in one place only), the suite silently goes nowhere and the
    /// host app falls back to its own picker.
    private static let appGroupID = "group.app.ananse.keyboard"

    /// UserDefaults keys remembering the last layout, glyph style, output
    /// script, and hanging-line weight between sessions. Restored from the
    /// extension's own defaults; style and hanging line are ALSO written to
    /// the App Group suite for the host app's preview.
    private enum PrefKey {
        static let layout = "AnanseKeyboard.layoutMode"
        static let style = "AnanseKeyboard.glyphStyle"
        static let script = "AnanseKeyboard.outputScript"
        static let hangingLine = "AnanseKeyboard.hangingLineWeight"
        static let glyphColor = "AnanseKeyboard.glyphColor"
        static let autoValues = "AnanseKeyboard.autoValues"
    }

    private var selectedFamily: FamilyId = .vowel
    private var headButtons: [FamilyId: KeyButton] = [:]
    private var strokeButtons: [Position: KeyButton] = [:]
    private let longPressDuration: TimeInterval = 0.3
    /// Second tap on the same head within this window types its root letter
    /// (mirrors the web keyboard's DOUBLE_CLICK_MS).
    private let doubleTapWindow: TimeInterval = 0.4
    /// One pending single-tap shared by ALL heads, so tapping a different head
    /// cancels the previous head's half-finished double-tap.
    private var pendingHeadTap: (family: FamilyId, at: Date)? = nil

    /// Output script: what gets committed to the host app. Ananse (default)
    /// inserts the glyph-mapped Latin; English inserts the plain-English reading
    /// so people without the Ananse font can read it. Mirrors the web app's
    /// on-keyboard "⇄" toggle.
    private enum OutputScript: String { case ananse, english }
    private var script: OutputScript = .ananse
    private var scriptButton: UIButton?
    /// Session-only shift state. Ananse capitals are stored as lowercase Latin;
    /// one-shot shift resets after the next letter while caps remains active.
    private enum ShiftState {
        case off, oneShot, caps
    }
    private var shiftState: ShiftState = .off
    private var shiftButton: UIButton?
    /// This only controls the companion app's preview. UIInputViewController
    /// has no annotation channel for host apps, so number keys still commit
    /// plain ASCII digits.
    private var autoValues = true

    private var keyboardStack: UIStackView?
    private var heightConstraint: NSLayoutConstraint?
    private var showsAppearanceControls = false

    private let blue = UIColor(red: 0x1a / 255, green: 0x3a / 255, blue: 0x8f / 255, alpha: 1)
    private let lightBlue = UIColor(red: 0xee / 255, green: 0xf2 / 255, blue: 0xff / 255, alpha: 1)

    /// The chosen glyph ink, drawing the key glyphs (and their hanging line).
    private var ink: UIColor { glyphColor.uiColor }

    private var ananseFontName: String? { AnanseFont.fontName(for: style) }
    private var fontDiagnostic: String? {
        ananseFontName == nil ? "\(style.displayName) font unavailable" : nil
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor(white: 0.85, alpha: 1)
        restorePreferences()
        rebuildKeyboard()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        let previous = preferenceSnapshot
        restorePreferences()
        if isViewLoaded, previous != preferenceSnapshot {
            rebuildKeyboard()
        }
    }

    private var preferenceSnapshot: [String] {
        [
            layoutMode.rawValue, style.rawValue, script.rawValue,
            hangingLine.rawValue, glyphColor.rawValue, String(autoValues),
        ]
    }

    /// Restore the last-used layout, glyph style, and output script saved by a
    /// previous session.
    private func restorePreferences() {
        let defaults = UserDefaults.standard
        let shared = UserDefaults(suiteName: KeyboardViewController.appGroupID)
        func source(for key: String) -> UserDefaults {
            shared?.object(forKey: key) != nil ? shared! : defaults
        }
        if let raw = source(for: PrefKey.layout).string(forKey: PrefKey.layout),
           let saved = LayoutMode(rawValue: raw) {
            layoutMode = saved
        }
        if let raw = source(for: PrefKey.style).string(forKey: PrefKey.style),
           let saved = GlyphStyle(rawValue: raw) {
            style = saved
        }
        if let raw = source(for: PrefKey.script).string(forKey: PrefKey.script),
           let saved = OutputScript(rawValue: raw) {
            script = saved
        }
        if let raw = source(for: PrefKey.hangingLine).string(forKey: PrefKey.hangingLine),
           let saved = HangingLineWeight(rawValue: raw) {
            hangingLine = saved
        }
        if let raw = source(for: PrefKey.glyphColor).string(forKey: PrefKey.glyphColor),
           let saved = GlyphColor(rawValue: raw) {
            glyphColor = saved
        }
        let valueSource = source(for: PrefKey.autoValues)
        if valueSource.object(forKey: PrefKey.autoValues) != nil {
            autoValues = valueSource.bool(forKey: PrefKey.autoValues)
        }
        // Also migrate whichever side supplied each value to the other store.
        // This makes a host-side edit the extension's durable local fallback.
        savePreferences()
    }

    /// Save the current layout, glyph style, and output script so the next
    /// session restores them.
    private func savePreferences() {
        let defaults = UserDefaults.standard
        defaults.set(layoutMode.rawValue, forKey: PrefKey.layout)
        defaults.set(style.rawValue, forKey: PrefKey.style)
        defaults.set(script.rawValue, forKey: PrefKey.script)
        defaults.set(hangingLine.rawValue, forKey: PrefKey.hangingLine)
        defaults.set(glyphColor.rawValue, forKey: PrefKey.glyphColor)
        defaults.set(autoValues, forKey: PrefKey.autoValues)
        // Every preference is mirrored both ways. This lets either process be
        // the most recent editor without leaving extension-only stale values.
        if let shared = UserDefaults(suiteName: KeyboardViewController.appGroupID) {
            shared.set(layoutMode.rawValue, forKey: PrefKey.layout)
            shared.set(style.rawValue, forKey: PrefKey.style)
            shared.set(script.rawValue, forKey: PrefKey.script)
            shared.set(hangingLine.rawValue, forKey: PrefKey.hangingLine)
            shared.set(glyphColor.rawValue, forKey: PrefKey.glyphColor)
            shared.set(autoValues, forKey: PrefKey.autoValues)
        }
    }

    // MARK: - Layout

    /// (Re)build the whole keyboard for the current layout mode and style.
    private func rebuildKeyboard() {
        keyboardStack?.removeFromSuperview()
        headButtons.removeAll()
        strokeButtons.removeAll()
        scriptButton = nil
        shiftButton = nil

        var rows: [UIView] = []
        switch layoutMode {
        case .families:
            for family in Ananse.familyOrder {
                rows.append(buildFamilyRow(family))
            }
        case .strokes:
            let headRow = makeRow(spacing: 4)
            for family in Ananse.familyOrder {
                let button = makeKeyButton()
                configureHead(button, family: family)
                headButtons[family] = button
                headRow.addArrangedSubview(button)
            }
            let strokeRow = makeRow(spacing: 4)
            for position in Ananse.strokeOrder {
                let button = makeKeyButton()
                configureStroke(button, position: position)
                strokeButtons[position] = button
                strokeRow.addArrangedSubview(button)
            }
            rows = [headRow, strokeRow]
        case .qwerty:
            for rowLetters in Ananse.qwertyRows {
                let row = makeRow(spacing: 4)
                for letter in rowLetters {
                    let button = makeKeyButton()
                    configureQwertyKey(button, letter: letter)
                    row.addArrangedSubview(button)
                }
                rows.append(row)
            }
        }
        // Families stays at four compact labeled rows plus utilities. Numerals
        // and appearance controls remain one layout-cycle away in the other
        // two modes instead of forcing Families into an oversized sixth row.
        if layoutMode != .families {
            rows.append(
                showsAppearanceControls ? buildAppearanceRow() : makeNumberRow()
            )
        }
        rows.append(buildUtilityRow())

        let stack = UIStackView(arrangedSubviews: rows)
        stack.axis = .vertical
        stack.spacing = 4
        stack.distribution = .fillEqually
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        keyboardStack = stack

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 4),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -4),
            stack.topAnchor.constraint(equalTo: view.topAnchor, constant: 6),
            stack.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -6),
        ])

        // Stay within the usual system keyboard envelope. Priority 999
        // so the system-imposed height never conflicts — the stack just fills
        // whatever height is granted.
        let height: CGFloat
        switch layoutMode {
        case .strokes: height = 236
        case .qwerty: height = 288
        case .families: height = 252
        }
        heightConstraint?.isActive = false
        let constraint = view.heightAnchor.constraint(equalToConstant: height)
        constraint.priority = UILayoutPriority(999)
        constraint.isActive = true
        heightConstraint = constraint

        refreshScriptButton()
        if layoutMode == .strokes { refreshSelection() }
    }

    private func makeRow(spacing: CGFloat) -> UIStackView {
        let row = UIStackView()
        row.axis = .horizontal
        row.spacing = spacing
        row.distribution = .fillEqually
        return row
    }

    private func makeKeyButton() -> KeyButton {
        let button = KeyButton(frame: .zero)
        button.hangingLineEm = hangingLine.emFactor
        button.backgroundColor = .white
        button.layer.cornerRadius = 6
        button.layer.shadowColor = UIColor.black.cgColor
        button.layer.shadowOpacity = 0.08
        button.layer.shadowRadius = 1
        button.layer.shadowOffset = CGSize(width: 0, height: 1)
        return button
    }

    private func bundledFont(size: CGFloat) -> UIFont? {
        guard let name = ananseFontName else { return nil }
        return UIFont(name: name, size: size)
    }

    private func showMissingFont(on button: KeyButton) {
        button.setTitle("⚠︎", for: .normal)
        button.setTitleColor(.systemRed, for: .normal)
        button.titleLabel?.font = .systemFont(ofSize: 17, weight: .bold)
        button.glyphFont = nil
        button.glyphText = ""
        button.accessibilityLabel = fontDiagnostic
    }

    private func buildFamilyRow(_ family: FamilyId) -> UIStackView {
        let group = UIStackView()
        group.axis = .vertical
        group.spacing = 1

        let label = UILabel()
        label.text = Ananse.familyShortName(family)
        label.font = .systemFont(ofSize: 8, weight: .bold)
        label.textColor = blue.withAlphaComponent(0.7)
        label.accessibilityElementsHidden = true
        label.heightAnchor.constraint(equalToConstant: 9).isActive = true
        group.addArrangedSubview(label)

        let row = makeRow(spacing: 4)
        for letter in Ananse.letters(for: family) {
            let button = makeKeyButton()
            configureFamilyLetter(button, letter: letter)
            row.addArrangedSubview(button)
        }
        group.addArrangedSubview(row)
        return group
    }

    private func configureFamilyLetter(_ button: KeyButton, letter: AnanseLetter) {
        button.accessibilityIdentifier = letter.english
        button.addTarget(self, action: #selector(familyLetterTapped(_:)), for: .touchUpInside)
        guard let glyphFont = bundledFont(size: 18) else {
            showMissingFont(on: button)
            return
        }
        button.glyphFont = glyphFont
        button.glyphText = letter.english
        let title = NSMutableAttributedString(
            string: letter.english + "\n",
            attributes: [.font: glyphFont, .foregroundColor: ink]
        )
        title.append(NSAttributedString(
            string: letter.english,
            attributes: [
                .font: UIFont.systemFont(ofSize: 9, weight: .bold),
                .foregroundColor: ink,
            ]
        ))
        button.setAttributedTitle(title, for: .normal)
        button.titleLabel?.numberOfLines = 2
        button.titleLabel?.textAlignment = .center
        button.accessibilityLabel = "Letter \(letter.english), \(Ananse.familyShortName(letter.family).lowercased()) family"
    }

    @objc private func familyLetterTapped(_ sender: UIButton) {
        guard let letter = sender.accessibilityIdentifier else { return }
        commit(Ananse.textToInsert(for: letter))
    }

    private func makeUtilityButton(title: String) -> UIButton {
        let button = UIButton(type: .system)
        button.setTitle(title, for: .normal)
        button.setTitleColor(blue, for: .normal)
        button.titleLabel?.font = .systemFont(ofSize: 16)
        button.titleLabel?.adjustsFontSizeToFitWidth = true
        button.titleLabel?.minimumScaleFactor = 0.6
        button.backgroundColor = UIColor(white: 0.92, alpha: 1)
        button.layer.cornerRadius = 6
        return button
    }

    private func buildAppearanceRow() -> UIStackView {
        let appearanceRow = makeRow(spacing: 4)
        // Style cycle: shows the current glyph design's name.
        let styleKey = makeUtilityButton(
            title: fontDiagnostic == nil ? style.displayName : "Font unavailable"
        )
        styleKey.titleLabel?.font = .systemFont(ofSize: 13, weight: .semibold)
        styleKey.accessibilityLabel = fontDiagnostic.map {
            "\($0). Tap for the next design"
        } ?? "Glyph style: \(style.displayName) — tap for the next design"
        styleKey.addTarget(self, action: #selector(cycleStyle), for: .touchUpInside)

        // Hanging-line key: cycles the Ananse Hanging Line drawn over the key
        // glyphs — Off → Thin → Medium → Thick, same weights as the web app.
        let hangingKey = makeUtilityButton(title: "‾ \(hangingLine.displayName)")
        hangingKey.titleLabel?.font = .systemFont(ofSize: 13, weight: .semibold)
        hangingKey.accessibilityLabel = hangingLine == .off
            ? "Ananse Hanging Line: off — tap to show a thin line"
            : "Ananse Hanging Line: \(hangingLine.displayName) — tap for the next weight"
        hangingKey.addTarget(self, action: #selector(cycleHangingLine), for: .touchUpInside)

        // Ink key: cycles the glyph color — Red → Gold → Green → Black, the
        // same curated palette as the web app. The dot shows the current ink.
        let colorKey = makeUtilityButton(title: "●")
        colorKey.setTitleColor(ink, for: .normal)
        colorKey.tintColor = ink
        colorKey.accessibilityLabel =
            "Glyph color: \(glyphColor.displayName) — tap for the next color"
        colorKey.addTarget(self, action: #selector(cycleGlyphColor), for: .touchUpInside)

        let autoValuesKey = makeUtilityButton(title: autoValues ? "Auto Values" : "Values Off")
        autoValuesKey.titleLabel?.font = .systemFont(ofSize: 11, weight: .semibold)
        autoValuesKey.accessibilityLabel = autoValues
            ? "Auto Values enabled in the companion preview. Host apps receive plain ASCII digits."
            : "Auto Values disabled. Host apps always receive plain ASCII digits."
        autoValuesKey.addTarget(self, action: #selector(toggleAutoValues), for: .touchUpInside)

        let scriptToggle = makeUtilityButton(title: scriptButtonTitle())
        scriptToggle.backgroundColor = .systemBlue
        scriptToggle.setTitleColor(.white, for: .normal)
        scriptToggle.titleLabel?.font = .systemFont(ofSize: 13, weight: .semibold)
        scriptToggle.addTarget(self, action: #selector(toggleScript), for: .touchUpInside)
        scriptButton = scriptToggle

        appearanceRow.addArrangedSubview(styleKey)
        appearanceRow.addArrangedSubview(hangingKey)
        appearanceRow.addArrangedSubview(colorKey)
        appearanceRow.addArrangedSubview(autoValuesKey)
        appearanceRow.addArrangedSubview(scriptToggle)
        return appearanceRow
    }

    private func buildUtilityRow() -> UIStackView {
        let utilityRow = makeRow(spacing: 4)
        utilityRow.distribution = .fill

        let nextKeyboard = makeUtilityButton(title: "")
        nextKeyboard.setImage(
            UIImage(systemName: "globe"),
            for: .normal
        )
        nextKeyboard.accessibilityLabel = "Next keyboard"
        nextKeyboard.addTarget(
            self,
            action: #selector(handleInputModeList(from:with:)),
            for: .allTouchEvents
        )
        nextKeyboard.widthAnchor.constraint(equalToConstant: 36).isActive = true

        // Layout cycle: labelled with the layout it switches TO.
        let nextLayout = layoutMode.next
        let layoutToggle = makeUtilityButton(title: nextLayout.displayName)
        layoutToggle.titleLabel?.font = .systemFont(ofSize: 13, weight: .semibold)
        layoutToggle.accessibilityLabel = "Switch to the \(nextLayout.displayName) layout"
        layoutToggle.addTarget(self, action: #selector(toggleLayout), for: .touchUpInside)
        layoutToggle.widthAnchor.constraint(equalToConstant: 62).isActive = true

        let appearanceToggle = makeUtilityButton(title: "")
        appearanceToggle.setImage(
            UIImage(systemName: showsAppearanceControls ? "textformat" : "slider.horizontal.3"),
            for: .normal
        )
        if layoutMode == .families {
            appearanceToggle.accessibilityLabel = "Show Ananse appearance controls in QWERTY"
        } else {
            appearanceToggle.accessibilityLabel = showsAppearanceControls
                ? "Show number row"
                : "Show Ananse appearance controls"
        }
        appearanceToggle.addTarget(
            self,
            action: #selector(toggleAppearanceControls),
            for: .touchUpInside
        )
        appearanceToggle.widthAnchor.constraint(equalToConstant: 36).isActive = true

        let shift = makeUtilityButton(title: shiftButtonTitle())
        shift.titleLabel?.font = .systemFont(ofSize: 15, weight: .semibold)
        shift.addTarget(self, action: #selector(cycleShift), for: .touchUpInside)
        shift.widthAnchor.constraint(equalToConstant: 36).isActive = true
        shiftButton = shift
        refreshShiftButton()

        let space = makeUtilityButton(title: "space")
        space.titleLabel?.font = .systemFont(ofSize: 15, weight: .semibold)
        space.addTarget(self, action: #selector(insertSpace), for: .touchUpInside)
        space.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let returnKey = makeUtilityButton(title: "↵")
        returnKey.accessibilityLabel = "Return"
        returnKey.addTarget(self, action: #selector(insertReturn), for: .touchUpInside)
        returnKey.widthAnchor.constraint(equalToConstant: 38).isActive = true

        let backspace = makeUtilityButton(title: "⌫")
        backspace.addTarget(self, action: #selector(handleBackspace), for: .touchUpInside)
        backspace.widthAnchor.constraint(equalToConstant: 44).isActive = true

        utilityRow.addArrangedSubview(nextKeyboard)
        utilityRow.addArrangedSubview(layoutToggle)
        utilityRow.addArrangedSubview(appearanceToggle)
        utilityRow.addArrangedSubview(shift)
        utilityRow.addArrangedSubview(space)
        utilityRow.addArrangedSubview(returnKey)
        utilityRow.addArrangedSubview(backspace)
        return utilityRow
    }

    @objc private func toggleAppearanceControls() {
        if layoutMode == .families {
            layoutMode = .qwerty
            showsAppearanceControls = true
            savePreferences()
            rebuildKeyboard()
            return
        }
        showsAppearanceControls.toggle()
        rebuildKeyboard()
    }

    // MARK: - Head keys (strokes layout)

    private func configureHead(_ button: KeyButton, family: FamilyId) {
        let root = Ananse.rootLetter(of: family)
        button.addTarget(self, action: #selector(headTapped(_:)), for: .touchUpInside)
        let longPress = UILongPressGestureRecognizer(target: self, action: #selector(headLongPressed(_:)))
        longPress.minimumPressDuration = longPressDuration
        button.addGestureRecognizer(longPress)
        button.tag = familyTag(family)
        guard let font = bundledFont(size: 22) else {
            showMissingFont(on: button)
            return
        }
        button.setTitle(root, for: .normal)
        button.setTitleColor(ink, for: .normal)
        button.titleLabel?.font = font
        button.glyphFont = font
        button.glyphText = root

    }

    @objc private func headTapped(_ sender: UIButton) {
        guard let family = familyForTag(sender.tag) else { return }
        let now = Date()
        if let pending = pendingHeadTap,
           pending.family == family,
           now.timeIntervalSince(pending.at) <= doubleTapWindow {
            // Second CONSECUTIVE tap on the same head — type its root letter.
            pendingHeadTap = nil
            commit(Ananse.textToInsert(for: Ananse.rootLetter(of: family)))
            return
        }
        // First tap (or a tap on a DIFFERENT head, which cancels the previous
        // head's pending double-tap) — select, and (re)arm.
        pendingHeadTap = (family: family, at: now)
        selectedFamily = family
        refreshSelection()
    }

    @objc private func headLongPressed(_ gesture: UILongPressGestureRecognizer) {
        guard gesture.state == .began, let button = gesture.view as? UIButton,
              let family = familyForTag(button.tag) else { return }
        pendingHeadTap = nil
        let root = Ananse.rootLetter(of: family)
        commit(Ananse.textToInsert(for: root))
    }

    // MARK: - Stroke keys (strokes layout)

    private func configureStroke(_ button: KeyButton, position: Position) {
        button.addTarget(self, action: #selector(strokeTapped(_:)), for: .touchUpInside)
        button.accessibilityIdentifier = position.rawValue
        guard let font = bundledFont(size: 22) else {
            showMissingFont(on: button)
            return
        }
        button.titleLabel?.font = font
        button.glyphFont = font
        button.setTitleColor(ink, for: .normal)
    }

    @objc private func strokeTapped(_ sender: UIButton) {
        guard let raw = sender.accessibilityIdentifier,
              let position = positionFromRaw(raw),
              let letter = Ananse.letter(family: selectedFamily, position: position) else { return }
        commit(Ananse.textToInsert(for: letter.english))
    }

    // MARK: - QWERTY keys

    /// A QWERTY key shows the Ananse symbol(s) that write its letter (drawn with
    /// the current style's font) above the Latin letter, and types the resolved
    /// output (C → S, Q → KW).
    private func configureQwertyKey(_ button: KeyButton, letter: String) {
        let output = Ananse.qwertyOutput(for: letter)
        button.accessibilityIdentifier = letter
        button.addTarget(self, action: #selector(qwertyTapped(_:)), for: .touchUpInside)
        let glyphSize: CGFloat = output.count > 1 ? 14 : 18
        guard let glyphFont = bundledFont(size: glyphSize) else {
            showMissingFont(on: button)
            return
        }
        button.glyphFont = glyphFont
        button.glyphText = output

        let title = NSMutableAttributedString(
            string: output + "\n",
            attributes: [.font: glyphFont, .foregroundColor: ink]
        )
        title.append(NSAttributedString(
            string: letter,
            attributes: [
                .font: UIFont.systemFont(ofSize: 10, weight: .bold),
                .foregroundColor: ink,
            ]
        ))
        button.setAttributedTitle(title, for: .normal)
        button.titleLabel?.numberOfLines = 2
        button.titleLabel?.textAlignment = .center
        button.accessibilityLabel = "Letter \(letter)"
    }

    @objc private func qwertyTapped(_ sender: UIButton) {
        guard let letter = sender.accessibilityIdentifier else { return }
        let output = Ananse.qwertyOutput(for: letter)
        guard !output.isEmpty else { return }
        commit(output)
    }

    // MARK: - Number keys (Ananse numerals)

    /// The number row: 1–9 then 0, phone-style. Every generated font carries
    /// the ten Ananse digit glyphs (one universal design shared by all
    /// styles), so the key face uses the current style's font directly.
    private func makeNumberRow() -> UIStackView {
        let row = makeRow(spacing: 4)
        for digit in ["1", "2", "3", "4", "5", "6", "7", "8", "9", "0"] {
            let button = makeKeyButton()
            configureNumberKey(button, digit: digit)
            row.addArrangedSubview(button)
        }
        return row
    }

    /// A number key shows the Ananse numeral (drawn with the current style's
    /// font) above a small Western digit label, mirroring the QWERTY keys.
    private func configureNumberKey(_ button: KeyButton, digit: String) {
        button.accessibilityIdentifier = digit
        button.addTarget(self, action: #selector(numberTapped(_:)), for: .touchUpInside)
        guard let glyphFont = bundledFont(size: 18) else {
            showMissingFont(on: button)
            return
        }
        button.glyphFont = glyphFont
        button.glyphText = digit

        let title = NSMutableAttributedString(
            string: digit + "\n",
            attributes: [.font: glyphFont, .foregroundColor: ink]
        )
        title.append(NSAttributedString(
            string: digit,
            attributes: [
                .font: UIFont.systemFont(ofSize: 10, weight: .bold),
                .foregroundColor: ink,
            ]
        ))
        button.setAttributedTitle(title, for: .normal)
        button.titleLabel?.numberOfLines = 2
        button.titleLabel?.textAlignment = .center
        button.accessibilityLabel = "Number \(digit)"
    }

    @objc private func numberTapped(_ sender: UIButton) {
        guard let digit = sender.accessibilityIdentifier else { return }
        // Digits pass through the output-script conversion unchanged, so the
        // committed text is the plain digit character in both scripts.
        commit(digit)
    }

    // MARK: - Utility keys

    @objc private func insertSpace() { textDocumentProxy.insertText(" ") }

    @objc private func insertReturn() { textDocumentProxy.insertText("\n") }

    @objc private func handleBackspace() { textDocumentProxy.deleteBackward() }

    @objc private func toggleLayout() {
        layoutMode = layoutMode.next
        savePreferences()
        rebuildKeyboard()
    }

    @objc private func cycleStyle() {
        style = style.next
        savePreferences()
        rebuildKeyboard()
    }

    @objc private func cycleHangingLine() {
        hangingLine = hangingLine.next
        savePreferences()
        rebuildKeyboard()
    }

    @objc private func cycleGlyphColor() {
        glyphColor = glyphColor.next
        savePreferences()
        rebuildKeyboard()
    }

    @objc private func toggleAutoValues() {
        autoValues.toggle()
        savePreferences()
        rebuildKeyboard()
    }

    private func shiftButtonTitle() -> String {
        switch shiftState {
        case .off: return "⇧"
        case .oneShot: return "⇧"
        case .caps: return "⇪"
        }
    }

    @objc private func cycleShift() {
        switch shiftState {
        case .off: shiftState = .oneShot
        case .oneShot: shiftState = .caps
        case .caps: shiftState = .off
        }
        refreshShiftButton()
    }

    private func refreshShiftButton() {
        guard let button = shiftButton else { return }
        button.setTitle(shiftButtonTitle(), for: .normal)
        button.backgroundColor = shiftState == .off ? UIColor(white: 0.92, alpha: 1) : .systemBlue
        button.setTitleColor(shiftState == .off ? blue : .white, for: .normal)
        switch shiftState {
        case .off: button.accessibilityLabel = "Shift off"
        case .oneShot: button.accessibilityLabel = "Shift on for the next letter"
        case .caps: button.accessibilityLabel = "Caps lock on"
        }
    }

    // MARK: - Output script (Ananse glyphs vs plain English)

    /// Commit typed text, honouring the current output script. Ananse mode
    /// inserts the glyph-mapped Latin as-is; English mode reads it back to plain
    /// English so people without the Ananse font can read it.
    private func commit(_ ananseText: String) {
        let containsLetter = ananseText.rangeOfCharacter(from: .letters) != nil
        let canonical = containsLetter && shiftState != .off
            ? ananseText.lowercased()
            : ananseText
        let out = script == .english ? Ananse.ananseToEnglish(canonical) : canonical
        textDocumentProxy.insertText(out)
        if containsLetter, shiftState == .oneShot {
            shiftState = .off
            refreshShiftButton()
        }
    }

    private func scriptButtonTitle() -> String {
        script == .ananse ? "⇄ Ananse" : "⇄ English"
    }

    @objc private func toggleScript() {
        script = script == .ananse ? .english : .ananse
        savePreferences()
        refreshScriptButton()
    }

    private func refreshScriptButton() {
        guard let button = scriptButton else { return }
        button.setTitle(scriptButtonTitle(), for: .normal)
        button.accessibilityLabel = script == .ananse
            ? "Typing Ananse — tap to type readable English instead"
            : "Typing English — tap to type Ananse instead"
    }

    // MARK: - Selection state (strokes layout)

    private func refreshSelection() {
        for (family, button) in headButtons {
            let isSelected = family == selectedFamily
            button.backgroundColor = isSelected ? UIColor.systemBlue : .white
            button.setTitleColor(isSelected ? .white : ink, for: .normal)
            button.setNeedsLayout() // recolor the hanging line with the title
        }
        for position in Ananse.strokeOrder {
            guard let button = strokeButtons[position] else { continue }
            let letter = Ananse.letter(family: selectedFamily, position: position)
            let fontAvailable = bundledFont(size: 22) != nil
            let glyph = fontAvailable ? (letter?.english ?? "") : "⚠︎"
            button.setTitle(glyph, for: .normal)
            button.glyphText = fontAvailable ? glyph : ""
            button.isEnabled = letter != nil
            button.backgroundColor = letter != nil ? .white : lightBlue
        }
    }

    // MARK: - Tag helpers

    private func familyTag(_ family: FamilyId) -> Int {
        Ananse.familyOrder.firstIndex(of: family) ?? 0
    }
    private func familyForTag(_ tag: Int) -> FamilyId? {
        Ananse.familyOrder.indices.contains(tag) ? Ananse.familyOrder[tag] : nil
    }
    private func positionFromRaw(_ raw: String) -> Position? {
        Ananse.strokeOrder.first { $0.rawValue == raw }
    }
}
