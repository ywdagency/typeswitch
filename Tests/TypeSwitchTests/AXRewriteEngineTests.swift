import ApplicationServices
import Testing
@testable import TypeSwitchApp

private final class FakeAXElement: AXElementProtocol {
    var role: String?
    var subrole: String?
    var isValueSettable: Bool
    var value: String?
    var selected: String?
    var range: CFRange?
    var ignoresWrites = false
    var isSelectedTextSettable = false
    var isSelectedTextRangeSettable = true
    var stringValueWriteCount = 0
    var selectedTextWriteCount = 0

    init(value: String?, selected: String? = nil, range: CFRange? = nil, isValueSettable: Bool = true, role: String? = nil, subrole: String? = nil) {
        self.value = value
        self.selected = selected
        self.range = range
        self.isValueSettable = isValueSettable
        self.role = role
        self.subrole = subrole
    }

    func stringValue() throws -> String? { value }
    func selectedText() throws -> String? { selected }
    func selectedTextRange() throws -> CFRange? { range }
    func setStringValue(_ value: String) throws {
        stringValueWriteCount += 1
        if ignoresWrites == false {
            self.value = value
        }
    }
    func setSelectedText(_ replacement: String) throws {
        guard isSelectedTextSettable,
              let value,
              let range,
              let replacementRange = AXRewriteEngine.range(from: range, in: value)
        else {
            throw AXElementError.unsupported
        }
        selectedTextWriteCount += 1
        self.value = value.replacingCharacters(in: replacementRange, with: replacement)
        self.range = CFRange(location: range.location + replacement.utf16.count, length: 0)
    }
    func setSelectedTextRange(_ range: CFRange) throws { self.range = range }
}

@Test
func replacesSelectedText() throws {
    let element = FakeAXElement(value: "hello world", selected: "world", range: CFRange(location: 6, length: 5))
    let engine = AXRewriteEngine()
    try engine.replaceSelectedText(in: element, replacement: "мир")
    #expect(element.value == "hello мир")
}

@Test
func replacesLastWordAtCaret() throws {
    let element = FakeAXElement(value: "hello ", range: CFRange(location: 6, length: 0))
    let engine = AXRewriteEngine()
    try engine.replaceLastWordAtCaret(in: element, replacement: "привет")
    #expect(element.value == "привет ")
    #expect(element.range?.location == 7)
}

@Test
func replacesLastWordAtEndOfValue() throws {
    let element = FakeAXElement(value: "hello", range: CFRange(location: 5, length: 0))
    let engine = AXRewriteEngine()
    try engine.replaceLastWordAtCaret(in: element, replacement: "привет")
    #expect(element.value == "привет")
    #expect(element.range?.location == 6)
}

@Test
func browserRewriteUsesSelectedTextWithoutWritingWholeValue() throws {
    let element = FakeAXElement(
        value: "before ghbdtn ",
        range: CFRange(location: 14, length: 0),
        role: kAXTextAreaRole as String
    )
    element.isSelectedTextSettable = true

    try AXRewriteEngine().replaceLastWordAtCaret(
        in: element,
        replacement: "привет",
        observedToken: "ghbdtn",
        strategy: .selectedTextOnly
    )

    #expect(element.value == "before привет ")
    #expect(element.stringValueWriteCount == 0)
    #expect(element.selectedTextWriteCount == 1)
    #expect(element.range?.location == 14)
    #expect(element.range?.length == 0)
}

@Test
func browserRewriteRefusesBeforeMutationWhenSelectedTextIsNotWritable() {
    let element = FakeAXElement(
        value: "ghbdtn ",
        range: CFRange(location: 7, length: 0),
        role: kAXTextAreaRole as String
    )

    #expect(throws: AXElementError.unsupported) {
        try AXRewriteEngine().replaceLastWordAtCaret(
            in: element,
            replacement: "привет",
            observedToken: "ghbdtn",
            strategy: .selectedTextOnly
        )
    }
    #expect(element.value == "ghbdtn ")
    #expect(element.stringValueWriteCount == 0)
}

@Test
func replacesObservedSuffixWhenCaretRangeIsOutOfValueBounds() throws {
    let element = FakeAXElement(value: "ghbdtn", range: CFRange(location: 20, length: 0))
    let engine = AXRewriteEngine()
    try engine.replaceLastWordAtCaret(in: element, replacement: "привет", observedToken: "ghbdtn")
    #expect(element.value == "привет")
}

@Test
func replacesObservedSuffixBeforeTrailingBoundary() throws {
    let element = FakeAXElement(value: "ghbdtn ", range: CFRange(location: 20, length: 0))
    let engine = AXRewriteEngine()
    try engine.replaceLastWordAtCaret(in: element, replacement: "привет", observedToken: "ghbdtn")
    #expect(element.value == "привет ")
    #expect(element.range?.location == 7)
}

@Test
func refusesStaleObservedTokenBeforeMutation() {
    let element = FakeAXElement(value: "hello ", range: CFRange(location: 6, length: 0))

    #expect(throws: AXElementError.staleValue) {
        try AXRewriteEngine().replaceLastWordAtCaret(
            in: element,
            replacement: "hello",
            observedToken: "руддщ"
        )
    }
    #expect(element.value == "hello ")
    #expect(element.stringValueWriteCount == 0)
}

@Test
func replacesObservedSuffixWithAmbiguousTrailingPunctuationBeforeWhitespace() throws {
    let element = FakeAXElement(value: "ghbdtn. ", range: CFRange(location: 8, length: 0))
    let engine = AXRewriteEngine()
    try engine.replaceLastWordAtCaret(in: element, replacement: "привет.", observedToken: "ghbdtn.")
    #expect(element.value == "привет. ")
    #expect(element.range?.location == 8)
}

@Test
func refusesLastWordRangeInEmptyValue() {
    #expect(AXRewriteEngine.lastWordRange(in: "", caretLocation: 0) == nil)
}

@Test
func refusesMissingSelectionForSelectedRewrite() {
    let element = FakeAXElement(value: "hello", range: nil)
    let engine = AXRewriteEngine()
    #expect(throws: AXElementError.missingSelection) {
        try engine.replaceSelectedText(in: element, replacement: "привет")
    }
}

@Test
func refusesReadOnlyFields() {
    let element = FakeAXElement(value: "hello", range: CFRange(location: 5, length: 0), isValueSettable: false)
    let engine = AXRewriteEngine()
    #expect(throws: AXElementError.notWritable) {
        try engine.replaceLastWordAtCaret(in: element, replacement: "привет")
    }
}

@Test
func refusesBeforeMutationWhenCaretCannotBeRestored() {
    let element = FakeAXElement(value: "ghbdtn ", range: CFRange(location: 7, length: 0))
    element.isSelectedTextRangeSettable = false

    #expect(throws: AXElementError.notWritable) {
        try AXRewriteEngine().replaceLastWordAtCaret(
            in: element,
            replacement: "привет",
            observedToken: "ghbdtn"
        )
    }
    #expect(element.value == "ghbdtn ")
    #expect(element.stringValueWriteCount == 0)
}

@Test
func refusesToReportSuccessWhenAxDoesNotConfirmTheWrite() {
    let element = FakeAXElement(value: "ghbdtn", range: CFRange(location: 6, length: 0))
    element.ignoresWrites = true
    let engine = AXRewriteEngine()

    #expect(throws: AXElementError.verificationFailed) {
        try engine.replaceLastWordAtCaret(in: element, replacement: "привет")
    }
}
