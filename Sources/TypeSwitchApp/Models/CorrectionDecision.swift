import Foundation

enum KeyboardLayout: String, CaseIterable, Codable, Equatable {
    case usEnglish
    case russian
    case ukrainian

    var displayName: String {
        switch self {
        case .usEnglish:
            "US English"
        case .russian:
            "Russian"
        case .ukrainian:
            "Ukrainian"
        }
    }
}

enum BlockedReason: String, Equatable, Codable, CaseIterable {
    case permissionsMissing
    case missingObservedToken
    case unsupportedLayout
    case insufficientConfidence
    case secureInput
    case passwordField
    case terminalLike
    case unsupportedAXContext
    case missingSelectionRange
    case missingFocusedElement
    case autoFixDisabled
    case perAppDisabled
    case ambiguousEditingState
    case rewriteFailed

    var userFacingDescription: String {
        switch self {
        case .permissionsMissing:
            "Required permissions are missing."
        case .missingObservedToken:
            "No text is available to correct."
        case .unsupportedLayout:
            "The current layout pair is not supported."
        case .insufficientConfidence:
            "Correction confidence is too low."
        case .secureInput:
            "Correction is blocked while secure input is active."
        case .passwordField:
            "Correction is blocked in secure or password-like fields."
        case .terminalLike:
            "Correction is blocked in terminal-like contexts."
        case .unsupportedAXContext:
            "The focused element does not expose a safe writable AX text model."
        case .missingSelectionRange:
            "The current selection or caret range is unavailable."
        case .missingFocusedElement:
            "No focused editable element was found."
        case .autoFixDisabled:
            "Auto-fix is currently disabled."
        case .perAppDisabled:
            "Auto-fix is disabled for this app."
        case .ambiguousEditingState:
            "The current editing state is too ambiguous to correct safely."
        case .rewriteFailed:
            "The text rewrite failed."
        }
    }
}

enum CorrectionDecision: Equatable {
    case ignore
    case switchOnly(targetLayout: KeyboardLayout, reason: String)
    case rewriteAndMaybeSwitch(replacement: String, targetLayout: KeyboardLayout, reason: String, confidence: Double)
    case blocked(BlockedReason)

    var confidence: Double? {
        switch self {
        case let .rewriteAndMaybeSwitch(_, _, _, confidence):
            confidence
        default:
            nil
        }
    }
}
