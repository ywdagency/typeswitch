import Foundation
import Testing
@testable import TypeSwitchApp

@Test
func syntheticFallbackPlanPreservesTrailingSpace() {
    let plan = SyntheticTextFallbackRewriteEngine.plan(
        observedToken: "ghbdtn",
        replacement: "привет",
        trailingDelimiter: " "
    )

    #expect(plan == SyntheticRewritePlan(deleteCount: 7, insertionText: "привет "))
}

@Test
func syntheticFallbackPlanSupportsUndoAfterDelimiterWasDeleted() {
    let plan = SyntheticTextFallbackRewriteEngine.plan(
        observedToken: "API",
        replacement: "ФЗШ",
        trailingDelimiter: ""
    )

    #expect(plan == SyntheticRewritePlan(deleteCount: 3, insertionText: "ФЗШ"))
}

@Test
func syntheticFallbackPlanPreservesTrailingPunctuation() {
    let plan = SyntheticTextFallbackRewriteEngine.plan(
        observedToken: "rfr",
        replacement: "как",
        trailingDelimiter: "."
    )

    #expect(plan == SyntheticRewritePlan(deleteCount: 4, insertionText: "как."))
}

@Test
func syntheticFallbackPlanPreservesAmbiguousPunctuationBeforeTrailingSpace() {
    let plan = SyntheticTextFallbackRewriteEngine.plan(
        observedToken: "ghbdtn.",
        replacement: "привет.",
        trailingDelimiter: " "
    )

    #expect(plan == SyntheticRewritePlan(deleteCount: 8, insertionText: "привет. "))
}

@Test
func syntheticFallbackPlanRefusesEmptyOrAmbiguousInput() {
    #expect(SyntheticTextFallbackRewriteEngine.plan(observedToken: "", replacement: "привет", trailingDelimiter: " ") == nil)
    #expect(SyntheticTextFallbackRewriteEngine.plan(observedToken: "ghbdtn", replacement: "", trailingDelimiter: " ") == nil)
    #expect(SyntheticTextFallbackRewriteEngine.plan(observedToken: "ghbdtn", replacement: "привет", trailingDelimiter: "  ") == nil)
}

@Test
func syntheticFallbackOnlyRecoversFromReadableAxModelFailures() {
    #expect(SyntheticTextFallbackRewriteEngine.canRecover(after: AXElementError.invalidRange))
    #expect(SyntheticTextFallbackRewriteEngine.canRecover(after: AXElementError.missingValue))
    #expect(SyntheticTextFallbackRewriteEngine.canRecover(after: AXElementError.unsupported))
    #expect(SyntheticTextFallbackRewriteEngine.canRecover(after: AXElementError.notWritable) == false)
    #expect(SyntheticTextFallbackRewriteEngine.canRecover(after: AXElementError.staleValue) == false)
    #expect(SyntheticTextFallbackRewriteEngine.canRecover(after: AXElementError.verificationFailed) == false)
    #expect(SyntheticTextFallbackRewriteEngine.canRecover(after: CocoaError(.fileReadNoPermission)) == false)
}

@Test
func syntheticFallbackConvertsReplacementToPhysicalTargetKeys() {
    #expect(SyntheticTextFallbackRewriteEngine.physicalInsertionText(
        for: "привіт ",
        targetLayout: .ukrainian
    ) == "ghbdsn ")
    #expect(SyntheticTextFallbackRewriteEngine.physicalInsertionText(
        for: "привет ",
        targetLayout: .russian
    ) == "ghbdtn ")
}
