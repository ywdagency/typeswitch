import Testing
@testable import TypeSwitchApp

@Test
func languageSwitchRequiresTwoConsecutiveSignals() {
    var tracker = LanguageSwitchEvidenceTracker()

    let firstUkrainian = tracker.confirms(target: .ukrainian, now: 0)
    let secondUkrainian = tracker.confirms(target: .ukrainian, now: 1)
    let firstRussian = tracker.confirms(target: .russian, now: 2)
    #expect(firstUkrainian == false)
    #expect(secondUkrainian)
    #expect(firstRussian == false)
    tracker.reset()
    let russianAfterReset = tracker.confirms(target: .russian, now: 3)
    #expect(russianAfterReset == false)
}

@Test
func languageSwitchEvidenceExpiresAfterTypingPause() {
    var tracker = LanguageSwitchEvidenceTracker()

    let first = tracker.confirms(target: .ukrainian, now: 0)
    let expired = tracker.confirms(target: .ukrainian, now: 9)
    let confirmed = tracker.confirms(target: .ukrainian, now: 10)
    #expect(first == false)
    #expect(expired == false)
    #expect(confirmed)
}
