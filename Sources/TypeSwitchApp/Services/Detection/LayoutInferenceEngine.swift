import Foundation

struct LayoutInferenceEngine {
    private static let latinLetters = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ")
    private static let russianLetters = CharacterSet(charactersIn: "абвгдеёжзийклмнопрстуфхцчшщъыьэюяіїєґАБВГДЕЁЖЗИЙКЛМНОПРСТУФХЦЧШЩЪЫЬЭЮЯІЇЄҐ")
    private static let ukrainianOnlyLetters = CharacterSet(charactersIn: "іїєґІЇЄҐ")
    private static let russianOnlyLetters = CharacterSet(charactersIn: "ыэъёЫЭЪЁ")

    private let mapper: LayoutMapper
    private let dictionaryStore: CorrectionDictionaryStore
    private let minimumConfidence: Double

    init(
        mapper: LayoutMapper = LayoutMapper(),
        dictionaryStore: CorrectionDictionaryStore? = nil,
        minimumConfidence: Double = AppConstants.minimumConfidence
    ) {
        self.mapper = mapper
        self.dictionaryStore = dictionaryStore ?? CorrectionDictionaryStore(mapper: mapper)
        self.minimumConfidence = minimumConfidence
    }

    func inferCorrection(
        for token: String,
        currentLayout: KeyboardLayout? = nil,
        requiresDictionaryMatch: Bool = false
    ) -> CorrectionDecision {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else {
            return .ignore
        }

        if looksLikeStructuredToken(trimmed) {
            return .ignore
        }

        let latinCount = scalarCount(in: trimmed, matching: Self.latinLetters)
        let cyrillicCount = scalarCount(in: trimmed, matching: Self.russianLetters)

        guard latinCount == 0 || cyrillicCount == 0 else {
            return .ignore
        }

        if let englishCyrillicDecision = englishCyrillicDecision(for: trimmed, currentLayout: currentLayout) {
            return englishCyrillicDecision
        }

        if let cyrillicEnglishDecision = cyrillicEnglishDecision(for: trimmed) {
            return cyrillicEnglishDecision
        }

        if let russianUkrainianDecision = russianUkrainianDecision(for: trimmed, currentLayout: currentLayout) {
            return russianUkrainianDecision
        }

        guard trimmed.rangeOfCharacter(from: Self.ukrainianOnlyLetters) == nil else {
            return .ignore
        }

        if let dictionaryRewrite = dictionaryRewrite(for: trimmed, currentLayout: currentLayout) {
            return dictionaryRewrite
        }

        if requiresDictionaryMatch {
            return .ignore
        }

        if latinCount > 0 {
            let mapped = mapper.mapToRussian(trimmed)
            guard mapped != trimmed else {
                return .ignore
            }
            let confidence = confidenceForLettersOnlyToken(trimmed)
            guard confidence >= minimumConfidence else {
                return .blocked(.insufficientConfidence)
            }
            return .rewriteAndMaybeSwitch(
                replacement: mapped,
                targetLayout: .russian,
                reason: "Detected a likely Russian word typed on the US English layout.",
                confidence: confidence
            )
        }

        if cyrillicCount > 0 {
            let mapped = mapper.mapToEnglish(trimmed)
            guard mapped != trimmed else {
                return .ignore
            }
            let confidence = confidenceForLettersOnlyToken(trimmed)
            guard confidence >= minimumConfidence else {
                return .blocked(.insufficientConfidence)
            }
            return .rewriteAndMaybeSwitch(
                replacement: mapped,
                targetLayout: .usEnglish,
                reason: "Detected a likely English word typed on the Russian layout.",
                confidence: confidence
            )
        }

        return .ignore
    }

    func learningCandidate(
        for token: String,
        currentLayout: KeyboardLayout?
    ) -> CorrectionDictionaryEntry? {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        let base = tokenSplitByTrailingPunctuation(trimmed).base

        guard (2...48).contains(base.count),
              looksLikeStructuredToken(base) == false,
              base.rangeOfCharacter(from: Self.ukrainianOnlyLetters) == nil,
              dictionaryStore.lookup(base, currentLayout: currentLayout) == nil
        else {
            return nil
        }

        let replacement: String
        let sourceLayout: KeyboardLayout
        let targetLayout: KeyboardLayout
        let language: CorrectionDictionaryLanguage
        let requiredReplacementCharacters: CharacterSet

        switch currentLayout {
        case .usEnglish:
            replacement = mapper.mapToRussian(base)
            sourceLayout = .usEnglish
            targetLayout = .russian
            language = .russian
            requiredReplacementCharacters = Self.russianLetters
        case .russian:
            replacement = mapper.mapToEnglish(base)
            sourceLayout = .russian
            targetLayout = .usEnglish
            language = .english
            requiredReplacementCharacters = Self.latinLetters
        case .ukrainian:
            return nil
        case .none:
            return nil
        }

        guard replacement != base,
              replacement.unicodeScalars.allSatisfy({ requiredReplacementCharacters.contains($0) })
        else {
            return nil
        }

        return CorrectionDictionaryEntry(
            wrongToken: base.lowercased(),
            correctToken: replacement.lowercased(),
            targetLayout: targetLayout,
            sourceLayout: sourceLayout,
            layoutPair: .usRussian,
            language: language,
            source: "user-learned"
        )
    }

    private func confidenceForLettersOnlyToken(_ token: String) -> Double {
        var confidence = 0.55
        if token.count >= 4 {
            confidence += 0.2
        } else if token.count == 3 {
            confidence += 0.1
        }

        if token.rangeOfCharacter(from: CharacterSet.decimalDigits) == nil {
            confidence += 0.05
        }

        if token.rangeOfCharacter(from: CharacterSet.punctuationCharacters) == nil {
            confidence += 0.05
        }

        return min(confidence, 0.95)
    }

    private func dictionaryRewrite(for token: String, currentLayout: KeyboardLayout?) -> CorrectionDecision? {
        if let dictionaryEntry = dictionaryStore.lookup(token, currentLayout: currentLayout) {
            return .rewriteAndMaybeSwitch(
                replacement: dictionaryEntry.correctToken,
                targetLayout: dictionaryEntry.targetLayout,
                reason: "Detected a dictionary-backed wrong-layout word.",
                confidence: 0.98
            )
        }

        let split = tokenSplitByTrailingPunctuation(token)
        guard split.base != token,
              let dictionaryEntry = dictionaryStore.lookup(split.base, currentLayout: currentLayout)
        else {
            return nil
        }

        return .rewriteAndMaybeSwitch(
            replacement: dictionaryEntry.correctToken + split.trailingPunctuation,
            targetLayout: dictionaryEntry.targetLayout,
            reason: "Detected a dictionary-backed wrong-layout word.",
            confidence: 0.98
        )
    }

    private func russianUkrainianDecision(
        for token: String,
        currentLayout: KeyboardLayout?
    ) -> CorrectionDecision? {
        guard let currentLayout,
              currentLayout == .russian || currentLayout == .ukrainian else {
            return nil
        }
        guard token.rangeOfCharacter(from: Self.latinLetters) == nil else {
            return nil
        }

        let sourceLayout: KeyboardLayout
        if token.rangeOfCharacter(from: Self.ukrainianOnlyLetters) != nil {
            sourceLayout = .ukrainian
        } else if token.rangeOfCharacter(from: Self.russianOnlyLetters) != nil {
            sourceLayout = .russian
        } else {
            sourceLayout = currentLayout
        }
        let targetLayout: KeyboardLayout = sourceLayout == .russian ? .ukrainian : .russian
        if dictionaryStore.contains(token, in: sourceLayout) == false {
            let mapped = mapper.map(token, from: sourceLayout, to: targetLayout)
            if mapped != token,
               dictionaryStore.contains(mapped, in: targetLayout),
               dictionaryStore.dominantRussianUkrainianLayout(for: mapped) == targetLayout
                    || containsDistinctiveLetter(for: targetLayout, in: mapped) {
                return .rewriteAndMaybeSwitch(
                    replacement: mapped,
                    targetLayout: targetLayout,
                    reason: "Detected a wrong Russian/Ukrainian keyboard layout.",
                    confidence: 0.98
                )
            }
        }

        guard dictionaryStore.dominantRussianUkrainianLayout(for: token) == targetLayout else {
            return nil
        }
        if targetLayout == .ukrainian {
            return .switchOnly(
                targetLayout: .ukrainian,
                reason: "Detected consecutive Ukrainian-only words."
            )
        }
        return .switchOnly(
            targetLayout: .russian,
            reason: "Detected consecutive Russian-only words."
        )
    }

    private func containsDistinctiveLetter(for layout: KeyboardLayout, in token: String) -> Bool {
        let letters: CharacterSet
        switch layout {
        case .russian:
            letters = CharacterSet(charactersIn: "ыэъёЫЭЪЁ")
        case .ukrainian:
            letters = CharacterSet(charactersIn: "іїєґІЇЄҐ")
        case .usEnglish:
            return false
        }
        return token.rangeOfCharacter(from: letters) != nil
    }

    private func englishCyrillicDecision(
        for token: String,
        currentLayout: KeyboardLayout?
    ) -> CorrectionDecision? {
        guard currentLayout == .usEnglish,
              token.rangeOfCharacter(from: Self.latinLetters) != nil,
              dictionaryStore.contains(token, in: .usEnglish) == false
        else {
            return nil
        }

        let russianCandidate = mapper.map(token, from: .usEnglish, to: .russian)
        let ukrainianCandidate = mapper.map(token, from: .usEnglish, to: .ukrainian)
        let russianMatch = dictionaryStore.contains(russianCandidate, in: .russian)
        let ukrainianMatch = dictionaryStore.contains(ukrainianCandidate, in: .ukrainian)

        let target: KeyboardLayout
        let replacement: String
        if russianMatch, ukrainianMatch == false {
            target = .russian
            replacement = russianCandidate
        } else if ukrainianMatch, russianMatch == false {
            target = .ukrainian
            replacement = ukrainianCandidate
        } else if russianMatch, ukrainianMatch, russianCandidate == ukrainianCandidate,
                  let dominant = dictionaryStore.frequencyDominantRussianUkrainianLayout(for: russianCandidate) {
            target = dominant
            replacement = russianCandidate
        } else {
            return nil
        }

        return .rewriteAndMaybeSwitch(
            replacement: replacement,
            targetLayout: target,
            reason: "Detected a dictionary-backed wrong-layout word.",
            confidence: 0.98
        )
    }

    private func cyrillicEnglishDecision(for token: String) -> CorrectionDecision? {
        guard token.rangeOfCharacter(from: Self.latinLetters) == nil,
              scalarCount(in: token, matching: Self.russianLetters) > 0,
              dictionaryStore.contains(token, in: .russian) == false,
              dictionaryStore.contains(token, in: .ukrainian) == false
        else {
            return nil
        }

        let candidates = Set([
            mapper.map(token, from: .russian, to: .usEnglish),
            mapper.map(token, from: .ukrainian, to: .usEnglish)
        ]).filter { candidate in
            candidate != token && dictionaryStore.contains(candidate, in: .usEnglish)
        }

        guard candidates.count == 1, let replacement = candidates.first else {
            return nil
        }

        return .rewriteAndMaybeSwitch(
            replacement: replacement,
            targetLayout: .usEnglish,
            reason: "Detected a dictionary-backed English word typed on a Cyrillic layout.",
            confidence: 0.98
        )
    }

    private func tokenSplitByTrailingPunctuation(_ token: String) -> (base: String, trailingPunctuation: String) {
        var base = token
        var trailingPunctuation = ""

        while let last = base.unicodeScalars.last,
              CharacterSet.punctuationCharacters.contains(last) {
            trailingPunctuation.insert(Character(last), at: trailingPunctuation.startIndex)
            base.removeLast()
        }

        return (base, trailingPunctuation)
    }

    private func looksLikeStructuredToken(_ token: String) -> Bool {
        if token.contains("://") || token.contains("@") || token.contains("\\") || token.contains("/") {
            return true
        }

        if token.contains(".") && token.contains(":") {
            return true
        }

        if token.contains("_") || token.contains("#") {
            return true
        }

        if token.rangeOfCharacter(from: .decimalDigits) != nil {
            return true
        }

        return false
    }

    private func scalarCount(in token: String, matching set: CharacterSet) -> Int {
        token.unicodeScalars.reduce(into: 0) { count, scalar in
            if set.contains(scalar) {
                count += 1
            }
        }
    }
}
