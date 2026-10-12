import AppKit
import Foundation

@MainActor
protocol LearningCandidateWordValidating {
    func recognizes(_ word: String, language: CorrectionDictionaryLanguage) -> Bool
}

@MainActor
struct SystemLearningCandidateWordValidator: LearningCandidateWordValidating {
    func recognizes(_ word: String, language: CorrectionDictionaryLanguage) -> Bool {
        let languageCode: String
        switch language {
        case .english:
            languageCode = "en"
        case .russian:
            languageCode = "ru"
        case .ukrainian:
            languageCode = "uk"
        }

        let checker = NSSpellChecker.shared
        guard let availableLanguage = checker.availableLanguages.first(where: {
            $0 == languageCode || $0.hasPrefix("\(languageCode)-")
        }) else {
            return false
        }

        let misspelledRange = checker.checkSpelling(
            of: word,
            startingAt: 0,
            language: availableLanguage,
            wrap: false,
            inSpellDocumentWithTag: 0,
            wordCount: nil
        )
        return misspelledRange.location == NSNotFound
    }
}

@MainActor
struct LearningCandidatePresentationPolicy {
    let validator: LearningCandidateWordValidating

    func shouldPresent(_ entry: CorrectionDictionaryEntry) -> Bool {
        validator.recognizes(entry.correctToken, language: entry.language)
    }
}
