import Foundation

struct PendingLearningCandidate: Equatable {
    let entry: CorrectionDictionaryEntry
    let frontmostBundleID: String
    let expiresAt: Date

    var isExpired: Bool {
        expiresAt <= Date()
    }
}
