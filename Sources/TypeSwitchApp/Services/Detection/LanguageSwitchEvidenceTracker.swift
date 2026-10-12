import Foundation

struct LanguageSwitchEvidenceTracker {
    private var target: KeyboardLayout?
    private var count = 0
    private var lastEvidenceTime: TimeInterval?
    private let timeout: TimeInterval = 8

    mutating func confirms(
        target newTarget: KeyboardLayout,
        now: TimeInterval = Date.timeIntervalSinceReferenceDate
    ) -> Bool {
        guard newTarget == .russian || newTarget == .ukrainian else {
            reset()
            return true
        }

        if let lastEvidenceTime, now - lastEvidenceTime > timeout {
            reset()
        }
        lastEvidenceTime = now

        if target == newTarget {
            count += 1
        } else {
            target = newTarget
            count = 1
        }

        if count >= 2 {
            reset()
            return true
        }
        return false
    }

    mutating func reset() {
        target = nil
        count = 0
        lastEvidenceTime = nil
    }
}
