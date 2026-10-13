import Testing
@testable import TypeSwitchApp

@Test
func infersRussianCorrectionFromLatinToken() {
    let engine = LayoutInferenceEngine()
    let decision = engine.inferCorrection(for: "ghbdtn")

    guard case let .rewriteAndMaybeSwitch(replacement, targetLayout, _, confidence) = decision else {
        Issue.record("Expected rewrite decision, got \(decision)")
        return
    }

    #expect(replacement == "привет")
    #expect(targetLayout == .russian)
    #expect(confidence >= AppConstants.minimumConfidence)
}

@Test
func infersEnglishCorrectionFromRussianToken() {
    let engine = LayoutInferenceEngine()
    let decision = engine.inferCorrection(for: "руддщ")

    guard case let .rewriteAndMaybeSwitch(replacement, targetLayout, _, _) = decision else {
        Issue.record("Expected rewrite decision, got \(decision)")
        return
    }

    #expect(replacement == "hello")
    #expect(targetLayout == .usEnglish)
}

@Test
func autoFixInfersShortEnglishWordSoFromRussianLayout() {
    let engine = LayoutInferenceEngine()
    let decision = engine.inferCorrection(
        for: "ыщ",
        currentLayout: .russian,
        requiresDictionaryMatch: true
    )

    guard case let .rewriteAndMaybeSwitch(replacement, targetLayout, _, confidence) = decision else {
        Issue.record("Expected dictionary-backed rewrite for ыщ → so, got \(decision)")
        return
    }

    #expect(replacement == "so")
    #expect(targetLayout == .usEnglish)
    #expect(confidence == 0.98)
}

@Test
func autoFixIgnoresWordsMissingFromDictionary() {
    let engine = LayoutInferenceEngine()
    #expect(engine.inferCorrection(for: "asdf", requiresDictionaryMatch: true) == .ignore)
}

@Test(arguments: [
    DictionaryLookupCase(input: "rjgbhjdfybtv", expected: "копированием"),
    DictionaryLookupCase(input: "Rjgbhjdfybtv", expected: "Копированием"),
    DictionaryLookupCase(input: "RJGBHJDFYBTV", expected: "КОПИРОВАНИЕМ"),
    DictionaryLookupCase(input: "rjgbhjdfybtv,", expected: "копированием,")
])
func autoFixRecognizesRussianCaseForms(testCase: DictionaryLookupCase) {
    let engine = LayoutInferenceEngine()
    let decision = engine.inferCorrection(
        for: testCase.input, currentLayout: .usEnglish, requiresDictionaryMatch: true
    )
    guard case let .rewriteAndMaybeSwitch(replacement, targetLayout, _, confidence) = decision else {
        Issue.record("Expected a dictionary-backed Russian inflection, got \(decision)")
        return
    }
    #expect(replacement == testCase.expected)
    #expect(targetLayout == .russian)
    #expect(confidence == 0.98)
    #expect(engine.learningCandidate(for: testCase.input, currentLayout: .usEnglish) == nil)
}

@Test
func russianCaseFormsPreserveRefusalsAndAlreadyValidWords() {
    let engine = LayoutInferenceEngine()
    let mapper = LayoutMapper()
    for word in ["копированиеом", "работаом", "новыйого", "словариями", "копировнием"] {
        #expect(engine.inferCorrection(
            for: mapper.mapToEnglish(word), currentLayout: .usEnglish, requiresDictionaryMatch: true
        ) == .ignore)
    }
    for token in ["entity", "next", "fhrb", "https://rjgbhjdfybtv.dev", "rjgbhjdfybtv@example.com"] {
        #expect(engine.inferCorrection(
            for: token, currentLayout: .usEnglish, requiresDictionaryMatch: true
        ) == .ignore)
    }
    #expect(engine.inferCorrection(
        for: "словарём", currentLayout: .russian, requiresDictionaryMatch: true
    ) == .ignore)
}

@Test
func dictionaryInferenceRespectsCurrentLayoutPair() {
    let engine = LayoutInferenceEngine()

    guard case let .rewriteAndMaybeSwitch(englishReplacement, englishTargetLayout, _, _) = engine.inferCorrection(
        for: "руддщ",
        currentLayout: .russian,
        requiresDictionaryMatch: true
    ) else {
        Issue.record("Expected Russian pair dictionary rewrite")
        return
    }

    let wrongDirectionDecision = engine.inferCorrection(
        for: "ghbdtn",
        currentLayout: .russian,
        requiresDictionaryMatch: true
    )

    #expect(englishReplacement == "hello")
    #expect(englishTargetLayout == .usEnglish)
    #expect(wrongDirectionDecision == .ignore)
}

@Test
func dictionaryInferenceHandlesWrongLayoutLetterPunctuationAndTrailingPunctuation() {
    let engine = LayoutInferenceEngine()

    guard case let .rewriteAndMaybeSwitch(firstReplacement, firstTargetLayout, _, _) = engine.inferCorrection(
        for: "[fq",
        requiresDictionaryMatch: true
    ) else {
        Issue.record("Expected dictionary rewrite for хай")
        return
    }

    guard case let .rewriteAndMaybeSwitch(secondReplacement, secondTargetLayout, _, _) = engine.inferCorrection(
        for: "ghbdtn,",
        requiresDictionaryMatch: true
    ) else {
        Issue.record("Expected dictionary rewrite with trailing punctuation")
        return
    }

    guard case let .rewriteAndMaybeSwitch(thirdReplacement, thirdTargetLayout, _, _) = engine.inferCorrection(
        for: "ghbdtn.",
        requiresDictionaryMatch: true
    ) else {
        Issue.record("Expected dictionary rewrite with trailing period")
        return
    }

    guard case let .rewriteAndMaybeSwitch(fourthReplacement, fourthTargetLayout, _, _) = engine.inferCorrection(
        for: "ghbdtn;",
        requiresDictionaryMatch: true
    ) else {
        Issue.record("Expected dictionary rewrite with trailing semicolon")
        return
    }

    #expect(firstReplacement == "хай")
    #expect(firstTargetLayout == .russian)
    #expect(secondReplacement == "привет,")
    #expect(secondTargetLayout == .russian)
    #expect(thirdReplacement == "привет.")
    #expect(thirdTargetLayout == .russian)
    #expect(fourthReplacement == "привет;")
    #expect(fourthTargetLayout == .russian)
}

@Test
func dictionaryInferenceHandlesDerivedEnglishPlurals() {
    let engine = LayoutInferenceEngine()

    guard case let .rewriteAndMaybeSwitch(replacement, targetLayout, _, _) = engine.inferCorrection(
        for: "ергьитфшды",
        currentLayout: .russian,
        requiresDictionaryMatch: true
    ) else {
        Issue.record("Expected derived plural dictionary rewrite")
        return
    }

    #expect(replacement == "thumbnails")
    #expect(targetLayout == .usEnglish)
}

@Test
func cyrillicEnglishInferenceIgnoresStaleRussianUkrainianSourceStatus() {
    let engine = LayoutInferenceEngine()

    for reportedLayout in [KeyboardLayout.russian, .ukrainian, .usEnglish] {
        let decision = engine.inferCorrection(
            for: "скнзещ",
            currentLayout: reportedLayout,
            requiresDictionaryMatch: true
        )
        guard case let .rewriteAndMaybeSwitch(replacement, targetLayout, _, _) = decision else {
            Issue.record("Expected crypto correction with reported layout \(reportedLayout), got \(decision)")
            continue
        }
        #expect(replacement == "crypto")
        #expect(targetLayout == .usEnglish)
    }

    #expect(engine.inferCorrection(
        for: "привет",
        currentLayout: .ukrainian,
        requiresDictionaryMatch: true
    ) == .ignore)

    guard case let .rewriteAndMaybeSwitch(abbreviation, targetLayout, _, _) = engine.inferCorrection(
        for: "ФЗШ",
        currentLayout: .russian,
        requiresDictionaryMatch: true
    ) else {
        Issue.record("Expected uppercase API correction")
        return
    }
    #expect(abbreviation == "API")
    #expect(targetLayout == .usEnglish)
}

@Test(arguments: [
    DictionaryLookupCase(input: "щт", expected: "on"),
    DictionaryLookupCase(input: "туц", expected: "new"),
    DictionaryLookupCase(input: "філ", expected: "ask"),
    DictionaryLookupCase(input: "філі", expected: "asks"),
    DictionaryLookupCase(input: "уес", expected: "etc"),
    DictionaryLookupCase(input: "рщт", expected: "hon"),
    DictionaryLookupCase(input: "ьуп", expected: "meg"),
    DictionaryLookupCase(input: "рьщ", expected: "hmo"),
    DictionaryLookupCase(input: "зоі", expected: "pjs")
])
func englishWordsAreNotBlockedByUkrainianDictionaryNoise(testCase: DictionaryLookupCase) {
    let engine = LayoutInferenceEngine()

    guard case let .rewriteAndMaybeSwitch(replacement, targetLayout, _, _) = engine.inferCorrection(
        for: testCase.input,
        currentLayout: .ukrainian,
        requiresDictionaryMatch: true
    ) else {
        Issue.record("Expected \(testCase.input) to map to English \(testCase.expected)")
        return
    }

    #expect(replacement == testCase.expected)
    #expect(targetLayout == .usEnglish)
}

@Test
func correctEnglishWordOnRemainsUnchanged() {
    let engine = LayoutInferenceEngine()
    #expect(engine.inferCorrection(
        for: "on",
        currentLayout: .usEnglish,
        requiresDictionaryMatch: true
    ) == .ignore)
}

@Test
func ignoresUkrainianOnlyLetters() {
    let engine = LayoutInferenceEngine()
    #expect(engine.inferCorrection(for: "привіт") == .ignore)
    #expect(engine.inferCorrection(for: "їх") == .ignore)
}

@Test
func russianUkrainianSwitchRequiresAnUnambiguousDictionaryWord() {
    let engine = LayoutInferenceEngine()

    guard case let .switchOnly(targetLayout, _) = engine.inferCorrection(
        for: "можна",
        currentLayout: .russian,
        requiresDictionaryMatch: true
    ) else {
        Issue.record("Expected an unambiguous Ukrainian switch signal")
        return
    }

    #expect(targetLayout == .ukrainian)
    #expect(engine.inferCorrection(for: "слово", currentLayout: .russian, requiresDictionaryMatch: true) == .ignore)
}

@Test
func russianUkrainianInferenceRewritesOnlyUniquePhysicalMapping() {
    let engine = LayoutInferenceEngine()

    guard case let .rewriteAndMaybeSwitch(replacement, targetLayout, _, _) = engine.inferCorrection(
        for: "грізть",
        currentLayout: .ukrainian,
        requiresDictionaryMatch: true
    ) else {
        Issue.record("Expected Ukrainian-to-Russian physical-layout correction")
        return
    }

    #expect(replacement == "грызть")
    #expect(targetLayout == .russian)
    #expect(engine.inferCorrection(for: "ті", currentLayout: .ukrainian, requiresDictionaryMatch: true) == .ignore)
    #expect(engine.inferCorrection(for: "слово", currentLayout: .russian, requiresDictionaryMatch: true) == .ignore)
}

@Test
func englishInferenceSelectsUkrainianWhenOnlyUkrainianCandidateExists() {
    let engine = LayoutInferenceEngine()

    guard case let .rewriteAndMaybeSwitch(replacement, targetLayout, _, _) = engine.inferCorrection(
        for: "ghbdsn",
        currentLayout: .usEnglish,
        requiresDictionaryMatch: true
    ) else {
        Issue.record("Expected English-to-Ukrainian correction")
        return
    }

    #expect(replacement == "привіт")
    #expect(targetLayout == .ukrainian)
}

@Test
func russianUkrainianInferenceAcceptsDistinctiveTargetLetterWithoutFrequencyMarker() {
    let engine = LayoutInferenceEngine()

    guard case let .rewriteAndMaybeSwitch(replacement, targetLayout, _, _) = engine.inferCorrection(
        for: "єротика",
        currentLayout: .ukrainian,
        requiresDictionaryMatch: true
    ) else {
        Issue.record("Expected distinctive-letter Ukrainian-to-Russian correction")
        return
    }

    #expect(replacement == "эротика")
    #expect(targetLayout == .russian)

    guard case let .rewriteAndMaybeSwitch(shortReplacement, shortTargetLayout, _, _) = engine.inferCorrection(
        for: "єхо",
        currentLayout: .ukrainian,
        requiresDictionaryMatch: true
    ) else {
        Issue.record("Expected short distinctive-letter Ukrainian-to-Russian correction")
        return
    }

    #expect(shortReplacement == "эхо")
    #expect(shortTargetLayout == .russian)

    guard case let .rewriteAndMaybeSwitch(staleSourceReplacement, staleSourceTarget, _, _) = engine.inferCorrection(
        for: "єхо",
        currentLayout: .russian,
        requiresDictionaryMatch: true
    ) else {
        Issue.record("Expected distinctive source letter to override a stale input-source reading")
        return
    }

    #expect(staleSourceReplacement == "эхо")
    #expect(staleSourceTarget == .russian)
    #expect(engine.inferCorrection(for: "ті", currentLayout: .ukrainian, requiresDictionaryMatch: true) == .ignore)
}

@Test
func ignoresStructuredTokens() {
    let engine = LayoutInferenceEngine()
    #expect(engine.inferCorrection(for: "ghbdtn@example.com") == .ignore)
    #expect(engine.inferCorrection(for: "https://ghbdtn.dev") == .ignore)
    #expect(engine.inferCorrection(for: "foo_bar") == .ignore)
}

@Test
func ignoresProtectedEnglishWordsThatLookLikeRussianDictionaryWords() {
    let engine = LayoutInferenceEngine()
    #expect(engine.inferCorrection(for: "her", currentLayout: .usEnglish, requiresDictionaryMatch: true) == .ignore)
}

@Test
func blocksLowConfidenceShortTokens() {
    let engine = LayoutInferenceEngine()
    #expect(engine.inferCorrection(for: "gh") == .blocked(.insufficientConfidence))
}

@Test
func createsLearningCandidateForDictionaryMiss() {
    let engine = LayoutInferenceEngine()

    let russianCandidate = engine.learningCandidate(for: "qzxv", currentLayout: .usEnglish)
    #expect(russianCandidate?.wrongToken == "qzxv")
    #expect(russianCandidate?.correctToken == "йячм")
    #expect(russianCandidate?.sourceLayout == .usEnglish)
    #expect(russianCandidate?.targetLayout == .russian)

    let englishCandidate = engine.learningCandidate(for: "йячм", currentLayout: .russian)
    #expect(englishCandidate?.correctToken == "qzxv")
    #expect(englishCandidate?.targetLayout == .usEnglish)
}

@Test
func refusesInvalidOrExistingLearningCandidate() {
    let engine = LayoutInferenceEngine()

    #expect(engine.learningCandidate(for: "ghbdtn", currentLayout: .usEnglish) == nil)
    #expect(engine.learningCandidate(for: "https://qzxv.dev", currentLayout: .usEnglish) == nil)
    #expect(engine.learningCandidate(for: "qzxv", currentLayout: nil) == nil)
    #expect(engine.learningCandidate(for: "a", currentLayout: .usEnglish) == nil)
}
