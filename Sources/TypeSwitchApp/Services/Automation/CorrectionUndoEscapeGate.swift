import Foundation

final class CorrectionUndoEscapeGate: @unchecked Sendable {
    private let lock = NSLock()
    private var expiresAt: Date?
    private var contextIsCurrent: (@Sendable () -> Bool)?
    private var revision: UInt64 = 0

    func arm(expiresAt: Date, contextIsCurrent: @escaping @Sendable () -> Bool) {
        lock.lock()
        defer { lock.unlock() }
        revision &+= 1
        self.expiresAt = expiresAt
        self.contextIsCurrent = contextIsCurrent
    }

    func invalidate() {
        lock.lock()
        defer { lock.unlock() }
        revision &+= 1
        expiresAt = nil
        contextIsCurrent = nil
    }

    func claim(now: Date = Date()) -> Bool {
        lock.lock()
        let expectedRevision = revision
        let eligible = expiresAt.map { $0 > now } == true
        let check = contextIsCurrent
        lock.unlock()
        let valid = eligible && check?() == true
        lock.lock()
        defer { lock.unlock() }
        guard revision == expectedRevision else { return false }
        revision &+= 1
        expiresAt = nil
        contextIsCurrent = nil
        return valid
    }
}
