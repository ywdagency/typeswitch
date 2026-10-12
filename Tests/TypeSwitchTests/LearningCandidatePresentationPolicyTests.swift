import Foundation
import Testing
@testable import TypeSwitchApp

@MainActor
@Test
func learningCandidateRequiresIndependentTargetWordRecognition() {
    let rejectedPolicy = LearningCandidatePresentationPolicy(
        validator: StubLearningCandidateWordValidator(recognizedWords: [])
    )
    let acceptedPolicy = LearningCandidatePresentationPolicy(
        validator: StubLearningCandidateWordValidator(recognizedWords: ["hello"])
    )
    let entry = CorrectionDictionaryEntry(
        wrongToken: "руддщ",
        correctToken: "hello",
        targetLayout: .usEnglish,
        sourceLayout: .russian,
        layoutPair: .usRussian,
        language: .english,
        source: "user-learned"
    )

    #expect(rejectedPolicy.shouldPresent(entry) == false)
    #expect(acceptedPolicy.shouldPresent(entry))
}

@MainActor
private struct StubLearningCandidateWordValidator: LearningCandidateWordValidating {
    let recognizedWords: Set<String>

    func recognizes(_ word: String, language: CorrectionDictionaryLanguage) -> Bool {
        recognizedWords.contains(word)
    }
}
