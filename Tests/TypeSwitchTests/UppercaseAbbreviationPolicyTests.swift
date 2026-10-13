import Testing
@testable import TypeSwitchApp

@Test
func knownUppercaseAbbreviationsAreProtectedOnlyInTheirSourceLanguage() {
    let engine = LayoutInferenceEngine()
    for (token, layout) in [("CEO", KeyboardLayout.usEnglish), ("API", .usEnglish), ("СССР", .russian), ("ЗСУ", .ukrainian)] {
        #expect(UppercaseAbbreviationPolicy.protects(token, layout: layout))
        #expect(engine.inferCorrection(for: token, currentLayout: layout, requiresDictionaryMatch: true) == .ignore)
        #expect(engine.inferCorrection(for: token + ",", currentLayout: layout, requiresDictionaryMatch: true) == .ignore)
        #expect(engine.learningCandidate(for: token, currentLayout: layout) == nil)
        #expect(UppercaseAbbreviationPolicy.protects(token.lowercased(), layout: layout) == false)
    }
    #expect(UppercaseAbbreviationPolicy.protects("CEO", layout: .russian) == false)
    #expect(UppercaseAbbreviationPolicy.protects("СССР", layout: .ukrainian) == false)
}

@Test
func uppercaseOrdinaryWordsAndWrongLayoutAbbreviationsStillCorrect() {
    let engine = LayoutInferenceEngine()
    for (token, expected, layout) in [("LFKMIT", "ДАЛЬШЕ", KeyboardLayout.usEnglish), ("GHBDTN", "ПРИВЕТ", .usEnglish), ("ФЗШ", "API", .russian)] {
        guard case let .rewriteAndMaybeSwitch(replacement, _, _, _) = engine.inferCorrection(for: token, currentLayout: layout, requiresDictionaryMatch: true) else {
            Issue.record("Expected an uppercase correction for the synthetic example")
            continue
        }
        #expect(replacement == expected)
    }
    #expect(UppercaseAbbreviationPolicy.protects("HELLO", layout: .usEnglish) == false)
    #expect(UppercaseAbbreviationPolicy.protects("МИР", layout: .russian) == false)
    #expect(UppercaseAbbreviationPolicy.protects("QZXV", layout: .usEnglish) == false)
}
