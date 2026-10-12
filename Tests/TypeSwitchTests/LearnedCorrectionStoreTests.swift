import Foundation
import Testing
@testable import TypeSwitchApp

@Test
func learnedCorrectionStorePersistsDeduplicatesAndRemoves() {
    let fixture = IsolatedUserDefaults()
    let store = LearnedCorrectionStore(defaults: fixture.defaults)
    let original = makeLearnedEntry(correctToken: "йячм")
    let replacement = makeLearnedEntry(correctToken: "пример")

    store.add(original)
    store.add(replacement)

    #expect(store.entries() == [replacement])
    #expect(store.lookup("QZXV", currentLayout: .usEnglish) == replacement)
    #expect(store.lookup("qzxv", currentLayout: .russian) == nil)

    store.remove(id: replacement.id)
    #expect(store.entries().isEmpty)
}

@Test
func dictionaryStoreReadsLearnedCorrections() {
    let fixture = IsolatedUserDefaults()
    let learnedStore = LearnedCorrectionStore(defaults: fixture.defaults)
    let entry = makeLearnedEntry(correctToken: "йячм")
    learnedStore.add(entry)

    let dictionaryStore = CorrectionDictionaryStore(learnedStore: learnedStore)

    #expect(dictionaryStore.lookup("qzxv", currentLayout: .usEnglish)?.correctToken == "йячм")
}

@Test
func pendingLearningCandidateExpires() {
    let pending = PendingLearningCandidate(
        entry: makeLearnedEntry(correctToken: "йячм"),
        frontmostBundleID: "com.example.App",
        expiresAt: Date(timeIntervalSinceNow: -1)
    )

    #expect(pending.isExpired)
}

private func makeLearnedEntry(correctToken: String) -> CorrectionDictionaryEntry {
    CorrectionDictionaryEntry(
        wrongToken: "qzxv",
        correctToken: correctToken,
        targetLayout: .russian,
        sourceLayout: .usEnglish,
        layoutPair: .usRussian,
        language: .russian,
        source: "user-learned"
    )
}
