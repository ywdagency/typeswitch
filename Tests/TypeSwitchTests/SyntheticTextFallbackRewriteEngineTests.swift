import CoreGraphics
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

@Test(arguments: ["дальше ", "Дальше ", "ДАЛЬШЕ ", "ДаЛьшЕ "])
func syntheticFallbackEventsPreserveExactCase(text: String) throws {
    let pairs = try #require(SyntheticTextFallbackRewriteEngine.insertionEvents(
        for: text,
        targetLayout: .russian
    ))
    let keyCodes: [Int64] = [37, 3, 40, 46, 34, 17, 49]
    #expect(pairs.count == text.count)
    for ((events, character), keyCode) in zip(zip(pairs, text), keyCodes) {
        #expect(events.count == 2)
        #expect(events.map(\.type) == [.keyDown, .keyUp])
        let expectedFlags: CGEventFlags = character.isUppercase ? .maskShift : []
        for event in events {
            #expect(event.flags == expectedFlags)
            #expect(event.getIntegerValueField(.keyboardEventKeycode) == keyCode)
            #expect(event.getIntegerValueField(.eventSourceUserData) == AppConstants.syntheticEventMarker)
            #expect(unicodeText(of: event) == String(character))
        }
    }
}

@Test
func syntheticFallbackEventsPreserveShiftedPunctuationAndUkrainianText() throws {
    let text = "Привіт!"
    let pairs = try #require(SyntheticTextFallbackRewriteEngine.insertionEvents(
        for: text,
        targetLayout: .ukrainian
    ))
    for (events, character) in zip(pairs, text) {
        let expectedFlags: CGEventFlags = character.isUppercase || character == "!" ? .maskShift : []
        for event in events {
            #expect(event.flags == expectedFlags)
            #expect(unicodeText(of: event) == String(character))
        }
    }
}

@Test
func syntheticFallbackEventsRefuseUnsupportedCharactersBeforePosting() {
    #expect(SyntheticTextFallbackRewriteEngine.insertionEvents(for: "привет🙂", targetLayout: .russian) == nil)
}

private func unicodeText(of event: CGEvent) -> String {
    var length = 0
    event.keyboardGetUnicodeString(maxStringLength: 0, actualStringLength: &length, unicodeString: nil)
    var buffer = [UniChar](repeating: 0, count: length)
    buffer.withUnsafeMutableBufferPointer { pointer in
        event.keyboardGetUnicodeString(
            maxStringLength: pointer.count,
            actualStringLength: &length,
            unicodeString: pointer.baseAddress
        )
    }
    return String(decoding: buffer.prefix(length), as: UTF16.self)
}
