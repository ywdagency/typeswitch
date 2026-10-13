import Foundation
import Testing
@testable import TypeSwitchApp

@Test
func immediateEscapeTakesRecentCorrectionOnce() {
    var tracker = AutoCorrectionUndoTracker()
    let now = Date()
    let candidate = makeUndoCandidate(expiresAt: now.addingTimeInterval(3))
    tracker.record(candidate)

    #expect(tracker.take(for: .undoCorrection, bundleID: candidate.bundleID, now: now) == candidate)
    #expect(tracker.take(for: .undoCorrection, bundleID: candidate.bundleID, now: now) == nil)
}

@Test
func correctionUndoExpiresAndRefusesAnotherApp() {
    var tracker = AutoCorrectionUndoTracker()
    let now = Date()
    tracker.record(makeUndoCandidate(expiresAt: now.addingTimeInterval(-1)))
    #expect(tracker.take(for: .undoCorrection, bundleID: "com.example.Editor", now: now) == nil)

    tracker.record(makeUndoCandidate(expiresAt: now.addingTimeInterval(3)))
    #expect(tracker.take(for: .undoCorrection, bundleID: "com.example.Other", now: now) == nil)
}

@Test
func completedUndoDoesNotPreventTrackingTheNextCorrection() {
    var tracker = AutoCorrectionUndoTracker()
    let now = Date()
    let candidate = makeUndoCandidate(expiresAt: now.addingTimeInterval(3))

    tracker.record(candidate)
    #expect(tracker.take(for: .undoCorrection, bundleID: candidate.bundleID, now: now) == candidate)

    tracker.record(candidate)
    #expect(tracker.take(for: .undoCorrection, bundleID: candidate.bundleID, now: now) == candidate)
}

@Test
func continuedTypingOrBackspaceInvalidatesTheUndoOpportunity() {
    var tracker = AutoCorrectionUndoTracker()
    let now = Date()
    let candidate = makeUndoCandidate(expiresAt: now.addingTimeInterval(3))
    for event in [NormalizedInputEvent.text("x"), .backspace, .navigation, .paste, .reset] {
        tracker.record(candidate)
        #expect(tracker.take(for: event, bundleID: candidate.bundleID, now: now) == nil)
        #expect(tracker.take(for: .undoCorrection, bundleID: candidate.bundleID, now: now) == nil)
    }
}

@Test
func escapeUndoRetainsTheDelimiterForBoundedFallback() {
    let candidate = makeUndoCandidate(expiresAt: .distantFuture)
    let plan = SyntheticTextFallbackRewriteEngine.plan(
        observedToken: candidate.replacementToken,
        replacement: candidate.originalToken,
        trailingDelimiter: candidate.trailingDelimiter
    )
    #expect(plan == SyntheticRewritePlan(deleteCount: 4, insertionText: "ФЗШ "))
}

private func makeUndoCandidate(expiresAt: Date) -> AutoCorrectionUndoCandidate {
    AutoCorrectionUndoCandidate(
        originalToken: "ФЗШ",
        replacementToken: "API",
        sourceLayout: .russian,
        targetLayout: .usEnglish,
        bundleID: "com.example.Editor",
        expiresAt: expiresAt
    )
}
