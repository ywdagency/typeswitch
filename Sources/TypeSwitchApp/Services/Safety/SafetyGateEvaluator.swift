import Foundation

@MainActor
struct SafetyGateEvaluator {
    let autoFixPolicy: WordBoundaryAutoFixPolicy

    func evaluate(
        request: CorrectionRequest,
        proposedDecision: CorrectionDecision,
        isAutoFixEnabled: Bool
    ) -> CorrectionDecision {
        switch proposedDecision {
        case .ignore, .switchOnly:
            return proposedDecision
        case let .blocked(reason):
            return .blocked(reason)
        case .rewriteAndMaybeSwitch:
            break
        }

        guard request.observedToken?.isEmpty == false else {
            return .blocked(.missingObservedToken)
        }

        if request.context.isSecureInput {
            return .blocked(.secureInput)
        }

        if request.context.isPasswordLike {
            return .blocked(.passwordField)
        }

        if request.context.isTerminalLike {
            return .blocked(.terminalLike)
        }

        if request.context.supportsWritableAXText == false {
            return .blocked(.unsupportedAXContext)
        }

        if request.selectionMode != .none && request.context.supportsSelectionRange == false {
            return .blocked(.missingSelectionRange)
        }

        if request.source == .autoWordBoundary,
           let blockedReason = autoFixPolicy.evaluate(context: request.context, isMasterEnabled: isAutoFixEnabled) {
            return .blocked(blockedReason)
        }

        return proposedDecision
    }
}
