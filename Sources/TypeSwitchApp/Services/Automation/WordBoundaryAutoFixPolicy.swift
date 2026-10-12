import Foundation

@MainActor
struct WordBoundaryAutoFixPolicy {
    let appPolicyStore: AppPolicyStore

    func evaluate(context: AppContext, isMasterEnabled: Bool) -> BlockedReason? {
        guard isMasterEnabled else {
            return .autoFixDisabled
        }

        guard appPolicyStore.mode(for: context.frontmostBundleID).allowsAutoFix else {
            return .perAppDisabled
        }

        return nil
    }
}
