@main
struct ValueNotationCheck {
    static func main() {
        func layout(_ value: String) -> AnanseValueLayout {
            AnanseValueNotation.automaticLayout(for: value, enabled: true)
        }

        func editableLayout(_ value: String) -> AnanseValueLayout {
            AnanseValueNotation.automaticEditableLayout(for: value, enabled: true)
        }

        let progressive = ["1", "10", "100", "1000", "10000", "100000", "1000000"]
            .map { layout($0).marks.first?.lower ?? 0 }
        precondition(progressive == [0, 0, 0, 1, 1, 1, 2])
        precondition(layout("1000000").displayText == "1")
        precondition(layout("1,000,000").marks.first?.lower == 2)
        precondition(layout("8,000,000,000").marks.first?.lower == 3)
        precondition(layout("8,000,000,000,000").marks.first?.lower == 4)

        // Editable layout preserves exactly the input text
        let ed = editableLayout("1,000,000")
        precondition(ed.displayText == "1,000,000")
        precondition(ed.marks.first?.characterOffset == 0)
        precondition(ed.marks.first?.lower == 2)

        let ed2 = editableLayout("1000000")
        precondition(ed2.displayText == "1000000")
        precondition(ed2.marks.first?.characterOffset == 0)
        precondition(ed2.marks.first?.lower == 2)

        let migrated = AnanseValueNotation.sanitize([
            AnanseManualValueAnnotation(characterOffset: 0, lower: 5),
            AnanseManualValueAnnotation(characterOffset: 1, lower: 6),
        ], for: "12")
        precondition(migrated.map(\.lower) == [3, 4])

        var manual = AnanseValueNotation.toggled([], at: 0, kind: "top", for: "8")
        manual = AnanseValueNotation.toggled(manual, at: 0, kind: "top", for: "8")
        manual = AnanseValueNotation.toggled(manual, at: 0, kind: "middle", for: "8")
        manual = AnanseValueNotation.toggled(manual, at: 0, kind: "middle", for: "8")
        manual = AnanseValueNotation.toggled(manual, at: 0, kind: "2", for: "8")
        manual = AnanseValueNotation.toggled(manual, at: 0, kind: "2", for: "8")
        precondition(manual.first?.top == true)
        precondition(manual.first?.middle == true)
        precondition(manual.first?.lower == 2)
        manual = AnanseValueNotation.toggled(manual, at: 0, kind: "4", for: "8")
        precondition(manual.first?.lower == 4)
        precondition(AnanseValueNotation.toggled(manual, at: 0, kind: "clear", for: "8").isEmpty)
        precondition(AnanseValueNotation.transform(manual, from: "8", to: "").isEmpty)
    }
}