import Foundation

struct BufferManager {
    private(set) var currentToken = ""

    static let wordBoundaryCharacters = CharacterSet.whitespacesAndNewlines.union(
        CharacterSet(charactersIn: "!?()/")
    )

    mutating func consume(_ event: NormalizedInputEvent) -> BufferMutationOutcome {
        switch event {
        case let .text(value):
            currentToken.append(value)
            return BufferMutationOutcome(currentToken: currentToken, completedToken: nil)
        case .backspace:
            if currentToken.isEmpty == false {
                currentToken.removeLast()
            }
            return BufferMutationOutcome(currentToken: currentToken, completedToken: nil)
        case .delimiter:
            let completed = currentToken.isEmpty ? nil : currentToken
            currentToken = ""
            return BufferMutationOutcome(currentToken: currentToken, completedToken: completed)
        case .navigation, .paste, .reset:
            currentToken = ""
            return BufferMutationOutcome(currentToken: currentToken, completedToken: nil)
        }
    }

    static func isWordBoundary(_ character: Character) -> Bool {
        character.unicodeScalars.allSatisfy { wordBoundaryCharacters.contains($0) }
    }
}
