import Foundation
import Testing
@testable import TypeSwitchApp

@Test
func correctionExceptionsPersistWithExactCaseAndLayout() {
    let fixture = IsolatedUserDefaults()
    let store = CorrectionExceptionStore(defaults: fixture.defaults)
    let entry = CorrectionException(token: "LFKMIT", layout: .usEnglish)
    store.add(entry)
    store.add(entry)
    let reloaded = CorrectionExceptionStore(defaults: fixture.defaults)
    #expect(reloaded.entries() == [entry])
    #expect(reloaded.contains("LFKMIT", layout: .usEnglish))
    #expect(reloaded.contains("lfkmit", layout: .usEnglish) == false)
    #expect(reloaded.contains("LFKMIT", layout: .russian) == false)
    reloaded.remove(id: entry.id)
    #expect(store.entries().isEmpty)
}

@Test
func correctionExceptionsRefuseWhitespaceAndControlCharacters() {
    let fixture = IsolatedUserDefaults()
    let store = CorrectionExceptionStore(defaults: fixture.defaults)
    for token in ["", "hello world", "hello\n", "hi\u{1b}", String(repeating: "a", count: 65)] {
        store.add(CorrectionException(token: token, layout: .usEnglish))
    }
    #expect(store.entries().isEmpty)
}

@Test
func correctionExceptionsOverrideAutomaticInferenceAndLearningOnly() {
    let fixture = IsolatedUserDefaults()
    let store = CorrectionExceptionStore(defaults: fixture.defaults)
    store.add(CorrectionException(token: "LFKMIT", layout: .usEnglish))
    let engine = LayoutInferenceEngine(exceptionStore: store)
    for token in ["LFKMIT", "LFKMIT,"] {
        #expect(engine.inferCorrection(for: token, currentLayout: .usEnglish, requiresDictionaryMatch: true) == .ignore)
        #expect(engine.learningCandidate(for: token, currentLayout: .usEnglish) == nil)
    }
    guard case .rewriteAndMaybeSwitch = engine.inferCorrection(for: "lfkmit", currentLayout: .usEnglish, requiresDictionaryMatch: true) else {
        Issue.record("An uppercase exception must not protect the lowercase word")
        return
    }
    guard case .rewriteAndMaybeSwitch = engine.inferCorrection(for: "LFKMIT", currentLayout: .usEnglish) else {
        Issue.record("Explicit correction must remain available")
        return
    }
    store.remove(id: store.entries()[0].id)
    #expect(engine.inferCorrection(for: "LFKMIT", currentLayout: .usEnglish, requiresDictionaryMatch: true) != .ignore)
}

@MainActor
@Test(arguments: ["ax", "fallback"])
func successfulEscapeUndoImmediatelyPersistsException(path: String) {
    let fixture = IsolatedUserDefaults()
    let store = CorrectionExceptionStore(defaults: fixture.defaults)
    let model = AppModel()
    let coordinator = LayoutCoordinator(appModel: model, correctionExceptionStore: store)
    let candidate = AutoCorrectionUndoCandidate(
        originalToken: "LFKMIT", replacementToken: "ДАЛЬШЕ",
        sourceLayout: .usEnglish, targetLayout: .russian,
        bundleID: "com.example.Editor", expiresAt: .distantFuture
    )
    #expect(store.entries().isEmpty)
    coordinator.completeAutoCorrectionUndo(candidate, path: path)
    let entry = CorrectionException(token: "LFKMIT", layout: .usEnglish)
    let reloadedStore = CorrectionExceptionStore(defaults: fixture.defaults)
    #expect(reloadedStore.entries() == [entry])
    #expect(model.correctionExceptions == [entry])
    let engine = LayoutInferenceEngine(exceptionStore: reloadedStore)
    #expect(engine.inferCorrection(for: "LFKMIT", currentLayout: .usEnglish, requiresDictionaryMatch: true) == .ignore)
    #expect(reloadedStore.contains("LFKMIT", layout: .russian) == false)
    #expect(reloadedStore.contains("lfkmit", layout: .usEnglish) == false)
    coordinator.completeAutoCorrectionUndo(candidate, path: path)
    #expect(reloadedStore.entries() == [entry])
    coordinator.removeCorrectionException(id: entry.id)
    #expect(reloadedStore.entries().isEmpty)
    #expect(model.correctionExceptions.isEmpty)
    #expect(engine.inferCorrection(for: "LFKMIT", currentLayout: .usEnglish, requiresDictionaryMatch: true) != .ignore)
}

@MainActor
@Test
func refusedEscapeUndoDoesNotPersistAnException() {
    let fixture = IsolatedUserDefaults()
    let store = CorrectionExceptionStore(defaults: fixture.defaults)
    let model = AppModel()
    let coordinator = LayoutCoordinator(appModel: model, correctionExceptionStore: store)
    let expired = AutoCorrectionUndoCandidate(
        originalToken: "LFKMIT", replacementToken: "ДАЛЬШЕ",
        sourceLayout: .usEnglish, targetLayout: .russian,
        bundleID: "com.example.Editor", expiresAt: .distantPast
    )
    coordinator.performAutoCorrectionUndo(expired, inputSequence: 0)
    #expect(store.entries().isEmpty)
    #expect(model.correctionExceptions.isEmpty)
}
