import Testing
@testable import TypeSwitchApp

@Test
func knownUppercaseAbbreviationsAreProtectedOnlyInTheirSourceLanguage() {
    let engine = LayoutInferenceEngine()
    for (token, layout) in [("CEO", KeyboardLayout.usEnglish), ("API", .usEnglish), ("USB", .usEnglish), ("SD", .usEnglish), ("SDI", .usEnglish), ("СССР", .russian), ("ЗСУ", .ukrainian)] {
        #expect(AbbreviationDictionary.contains(token, layout: layout))
        #expect(engine.inferCorrection(for: token, currentLayout: layout, requiresDictionaryMatch: true) == .ignore)
        #expect(engine.inferCorrection(for: token + ",", currentLayout: layout, requiresDictionaryMatch: true) == .ignore)
        #expect(engine.learningCandidate(for: token, currentLayout: layout) == nil)
        #expect(AbbreviationDictionary.contains(token.lowercased(), layout: layout) == false)
    }
    #expect(AbbreviationDictionary.contains("CEO", layout: .russian) == false)
    #expect(AbbreviationDictionary.contains("СССР", layout: .ukrainian) == false)
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
    #expect(AbbreviationDictionary.contains("HELLO", layout: .usEnglish) == false)
    #expect(AbbreviationDictionary.contains("МИР", layout: .russian) == false)
    #expect(AbbreviationDictionary.contains("QZXV", layout: .usEnglish) == false)
}

@Test(arguments: [KeyboardLayout.russian, .ukrainian])
func recognizesUSBSDAndSDIInCyrillicLayouts(layout: KeyboardLayout) {
    let engine = LayoutInferenceEngine()
    let examples = layout == .russian
        ? [("ГЫИ", "USB"), ("ЫВ", "SD"), ("ЫВШ", "SDI")]
        : [("ГІИ", "USB"), ("ІВ", "SD"), ("ІВШ", "SDI")]
    for (token, expected) in examples {
        for punctuation in ["", ",", ".", "!"] {
            let decision = engine.inferCorrection(
                for: token + punctuation, currentLayout: layout, requiresDictionaryMatch: true
            )
            guard case let .rewriteAndMaybeSwitch(replacement, target, _, confidence) = decision else {
                Issue.record("Expected a known abbreviation correction, got \(decision)")
                continue
            }
            #expect(replacement == expected + punctuation)
            #expect(target == .usEnglish)
            #expect(confidence >= AppConstants.minimumConfidence)
        }
        #expect(engine.learningCandidate(for: token, currentLayout: layout) == nil)
    }
}

@Test
func abbreviationRecognitionDoesNotDependOnOrdinaryWordLists() {
    let engine = LayoutInferenceEngine(dictionaryStore: CorrectionDictionaryStore(entries: []))
    for (token, source, expected, target) in [
        ("ЫВ", KeyboardLayout.russian, "SD", KeyboardLayout.usEnglish),
        ("ІВШ", .ukrainian, "SDI", .usEnglish),
        ("ГЫИ", .russian, "USB", .usEnglish),
        ("VDL", .usEnglish, "МВД", .russian),
        ("PCE", .usEnglish, "ЗСУ", .ukrainian)
    ] {
        guard case let .rewriteAndMaybeSwitch(replacement, layout, _, _) = engine.inferCorrection(
            for: token, currentLayout: source, requiresDictionaryMatch: true
        ) else {
            Issue.record("Expected recognition from the abbreviation dictionary alone")
            continue
        }
        #expect(replacement == expected)
        #expect(layout == target)
    }
}

@Test
func abbreviationRecognitionRefusesUnknownCaseStructuredAndAmbiguousTokens() {
    let engine = LayoutInferenceEngine(dictionaryStore: CorrectionDictionaryStore(entries: []))
    for token in ["ыв", "Ыв", "гыи", "ГыИ", "ЙЯЧМ", "ЫВ3", "ЫВ_", "ЫВ@", "ЫВ/", "ЫD"] {
        #expect(engine.inferCorrection(for: token, currentLayout: .russian, requiresDictionaryMatch: true) == .ignore)
    }
    // Both Cyrillic layouts have this abbreviation; neither target layout is unique.
    #expect(engine.inferCorrection(for: "JJY", currentLayout: .usEnglish, requiresDictionaryMatch: true) == .ignore)
    #expect(engine.learningCandidate(for: "JJY", currentLayout: .usEnglish) == nil)
    #expect(engine.inferCorrection(for: "ЫВ", currentLayout: nil, requiresDictionaryMatch: true) == .ignore)
    #expect(engine.inferCorrection(for: "PCE", currentLayout: .russian, requiresDictionaryMatch: true) == .ignore)
    #expect(engine.inferCorrection(for: "ЫВ", currentLayout: .ukrainian, requiresDictionaryMatch: true) == .ignore)
}

@Test
func abbreviationRecognitionPreservesValidSourceWordsAndCompetingWordTargets() {
    let engine = LayoutInferenceEngine()
    // These physical mappings produce TLS and CD, but the source words are already valid.
    for (token, layout) in [("ЕДЫ", KeyboardLayout.russian), ("СВ", .ukrainian)] {
        #expect(engine.inferCorrection(for: token, currentLayout: layout, requiresDictionaryMatch: true) == .ignore)
        #expect(engine.inferCorrection(for: token + ",", currentLayout: layout, requiresDictionaryMatch: true) == .ignore)
    }
    // СССР is an abbreviation in Russian and an ordinary dictionary entry in Ukrainian.
    #expect(engine.inferCorrection(for: "CCCP", currentLayout: .usEnglish, requiresDictionaryMatch: true) == .ignore)
}

@Test
func abbreviationRecognitionRespectsExactLayoutExceptions() {
    let fixture = IsolatedUserDefaults()
    let store = CorrectionExceptionStore(defaults: fixture.defaults)
    let entry = CorrectionException(token: "ЫВ", layout: .russian)
    store.add(entry)
    let engine = LayoutInferenceEngine(exceptionStore: store)
    for token in ["ЫВ", "ЫВ,"] {
        #expect(engine.inferCorrection(for: token, currentLayout: .russian, requiresDictionaryMatch: true) == .ignore)
        #expect(engine.learningCandidate(for: token, currentLayout: .russian) == nil)
    }
    #expect(engine.inferCorrection(for: "ІВ", currentLayout: .ukrainian, requiresDictionaryMatch: true) != .ignore)
    store.remove(id: entry.id)
    #expect(engine.inferCorrection(for: "ЫВ", currentLayout: .russian, requiresDictionaryMatch: true) != .ignore)
}
