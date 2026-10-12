import Foundation

struct AutoCorrectionUndoCandidate: Equatable {
    let originalToken: String
    let replacementToken: String
    let sourceLayout: KeyboardLayout
    let targetLayout: KeyboardLayout
    let bundleID: String
    let expiresAt: Date
}

struct AutoCorrectionUndoTracker {
    private var candidate: AutoCorrectionUndoCandidate?

    mutating func record(_ candidate: AutoCorrectionUndoCandidate) {
        self.candidate = candidate
    }

    mutating func takeForImmediateBackspace(bundleID: String, now: Date = Date()) -> AutoCorrectionUndoCandidate? {
        defer { candidate = nil }
        guard let candidate,
              candidate.bundleID == bundleID,
              candidate.expiresAt > now
        else {
            return nil
        }
        return candidate
    }

    mutating func invalidate() {
        candidate = nil
    }
}
