import Foundation

struct CorrectionFeedbackPolicy {
    static func shouldPlaySuccessSound(
        didRewriteText: Bool,
        soundFeedbackEnabled: Bool
    ) -> Bool {
        didRewriteText && soundFeedbackEnabled
    }
}
