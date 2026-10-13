import CoreGraphics
import Foundation

/// Access to the session and the input sequence is serialized with the event-tap callback.
final class RewriteInputQueue: @unchecked Sendable {
    struct HeldEvent {
        let event: CGEvent
        let sequence: UInt64?
    }

    final class Session {
        let identifier: UInt64
        let deadline: UInt64
        let isContextCurrent: @Sendable () -> Bool
        let completionEvent: CGEvent
        let timeoutEvent: CGEvent
        var events: [HeldEvent] = []
        var aborted = false
        var finishing = false

        init(identifier: UInt64, deadline: UInt64, isContextCurrent: @escaping @Sendable () -> Bool,
             completionEvent: CGEvent, timeoutEvent: CGEvent) {
            self.identifier = identifier
            self.deadline = deadline
            self.isContextCurrent = isContextCurrent
            self.completionEvent = completionEvent
            self.timeoutEvent = timeoutEvent
        }
    }

    enum Signal: Int64 {
        case completion = 1
        case timeout = 2
    }

    private static let markerPrefix: Int64 = 0x545800000000
    private static let identifierMask: UInt64 = 0x3FFFFFFF

    static func marker(identifier: UInt64, signal: Signal) -> Int64 {
        markerPrefix | Int64((identifier & identifierMask) << 2) | signal.rawValue
    }

    static func controlEvent(identifier: UInt64, signal: Signal) -> CGEvent? {
        guard let event = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: false) else { return nil }
        event.flags = []
        // Set source metadata once on a fresh event, including for timeout signals.
        event.setIntegerValueField(.eventSourceUserData, value: marker(identifier: identifier, signal: signal))
        return event
    }

    static func signal(from event: CGEvent) -> (identifier: UInt64, signal: Signal)? {
        let value = event.getIntegerValueField(.eventSourceUserData)
        guard value & ~Int64(0xFFFFFFFF) == markerPrefix,
              let signal = Signal(rawValue: value & 3)
        else { return nil }
        return (UInt64(value & 0xFFFFFFFF) >> 2, signal)
    }

    private let lock = NSRecursiveLock()
    let capacity: Int
    let timeoutNanoseconds: UInt64
    var session: Session?
    private var nextIdentifier: UInt64 = 0

    init(capacity: Int = 128, timeoutNanoseconds: UInt64 = 500_000_000) {
        precondition(capacity > 0 && timeoutNanoseconds > 0)
        self.capacity = capacity
        self.timeoutNanoseconds = timeoutNanoseconds
    }

    func synchronized<T>(_ operation: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return operation()
    }

    func begin(now: UInt64, isContextCurrent: @escaping @Sendable () -> Bool) -> Session? {
        guard session == nil, isContextCurrent() else { return nil }
        nextIdentifier = (nextIdentifier &+ 1) & Self.identifierMask
        guard let completion = Self.controlEvent(identifier: nextIdentifier, signal: .completion),
              let timeout = Self.controlEvent(identifier: nextIdentifier, signal: .timeout)
        else { return nil }
        let created = Session(identifier: nextIdentifier, deadline: now &+ timeoutNanoseconds,
                              isContextCurrent: isContextCurrent, completionEvent: completion, timeoutEvent: timeout)
        session = created
        return created
    }
}
