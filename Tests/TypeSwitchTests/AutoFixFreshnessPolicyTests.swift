import Testing
@testable import TypeSwitchApp

@Test
func autoFixFreshnessRequiresTheLatestInputSequence() {
    #expect(AutoFixFreshnessPolicy.isFresh(scheduledSequence: 7, latestSequence: 7))
    #expect(AutoFixFreshnessPolicy.isFresh(scheduledSequence: 7, latestSequence: 8) == false)
}

@Test
func observedTokenScriptMustMatchTheActiveLayout() {
    #expect(ObservedTokenLayoutPolicy.isConsistent("hello", with: .usEnglish))
    #expect(ObservedTokenLayoutPolicy.isConsistent("hello", with: .russian) == false)
    #expect(ObservedTokenLayoutPolicy.isConsistent("руддщ", with: .russian))
    #expect(ObservedTokenLayoutPolicy.isConsistent("руддщ", with: .ukrainian))
    #expect(ObservedTokenLayoutPolicy.isConsistent("руддщ", with: .usEnglish) == false)
}

@Test
func punctuationDoesNotCreateAFalseLayoutMismatch() {
    #expect(ObservedTokenLayoutPolicy.isConsistent("[fq", with: .usEnglish))
    #expect(ObservedTokenLayoutPolicy.isConsistent("руддщ,", with: .russian))
}
