import Foundation
import Testing
@testable import TypeSwitchApp

@Test
func immediateBackspaceTakesRecentCorrectionOnce() {
    var tracker = AutoCorrectionUndoTracker()
    let now = Date()
    let candidate = makeUndoCandidate(expiresAt: now.addingTimeInterval(3))
    tracker.record(candidate)

    #expect(tracker.takeForImmediateBackspace(bundleID: candidate.bundleID, now: now) == candidate)
    #expect(tracker.takeForImmediateBackspace(bundleID: candidate.bundleID, now: now) == nil)
}

@Test
func correctionUndoExpiresAndRefusesAnotherApp() {
    var tracker = AutoCorrectionUndoTracker()
    let now = Date()
    tracker.record(makeUndoCandidate(expiresAt: now.addingTimeInterval(-1)))
    #expect(tracker.takeForImmediateBackspace(bundleID: "com.example.Editor", now: now) == nil)

    tracker.record(makeUndoCandidate(expiresAt: now.addingTimeInterval(3)))
    #expect(tracker.takeForImmediateBackspace(bundleID: "com.example.Other", now: now) == nil)
}

@Test
func completedUndoDoesNotPreventTrackingTheNextCorrection() {
    var tracker = AutoCorrectionUndoTracker()
    let now = Date()
    let candidate = makeUndoCandidate(expiresAt: now.addingTimeInterval(3))

    tracker.record(candidate)
    #expect(tracker.takeForImmediateBackspace(bundleID: candidate.bundleID, now: now) == candidate)

    tracker.record(candidate)
    #expect(tracker.takeForImmediateBackspace(bundleID: candidate.bundleID, now: now) == candidate)
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
