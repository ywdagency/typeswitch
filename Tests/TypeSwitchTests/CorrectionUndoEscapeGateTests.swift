import Foundation
import Testing
@testable import TypeSwitchApp

@Test
func escapeUndoGatePassesOrdinaryEscapeAndClaimsEligibleUndoOnce() {
    let gate = CorrectionUndoEscapeGate()
    let now = Date()
    #expect(gate.claim(now: now) == false)
    gate.arm(expiresAt: now.addingTimeInterval(3)) { true }
    #expect(gate.claim(now: now))
    #expect(gate.claim(now: now) == false)
}

@Test
func escapeUndoGateRefusesExpiredChangedOrInvalidatedContext() {
    let gate = CorrectionUndoEscapeGate()
    let now = Date()
    gate.arm(expiresAt: now) { true }
    #expect(gate.claim(now: now) == false)
    gate.arm(expiresAt: now.addingTimeInterval(3)) { false }
    #expect(gate.claim(now: now) == false)
    gate.arm(expiresAt: now.addingTimeInterval(3)) { true }
    gate.invalidate()
    #expect(gate.claim(now: now) == false)
}

@Test
func escapeUndoGateRejectsInvalidationDuringContextCheck() {
    let gate = CorrectionUndoEscapeGate()
    gate.arm(expiresAt: .distantFuture) {
        gate.invalidate()
        return true
    }
    #expect(gate.claim() == false)
}
