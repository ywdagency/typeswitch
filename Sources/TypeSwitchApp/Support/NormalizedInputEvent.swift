import Foundation

struct MonitoredInputEvent: Equatable, Sendable {
    let sequence: UInt64
    let event: NormalizedInputEvent
}

enum NormalizedInputEvent: Equatable, Sendable {
    case text(String)
    case delimiter(Character)
    case backspace
    case navigation
    case paste
    case reset
}

struct BufferMutationOutcome: Equatable {
    var currentToken: String
    var completedToken: String?
}
