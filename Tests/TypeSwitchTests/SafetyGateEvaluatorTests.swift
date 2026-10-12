import Foundation
import Testing
@testable import TypeSwitchApp

@MainActor
@Test
func blocksSecureInput() {
    let fixture = makeSafetyGateFixture()
    let evaluator = fixture.evaluator
    let request = makeRequest(isSecureInput: true)
    let decision = evaluator.evaluate(request: request, proposedDecision: .rewriteAndMaybeSwitch(replacement: "привет", targetLayout: .russian, reason: "test", confidence: 0.9), isAutoFixEnabled: true)
    #expect(decision == .blocked(.secureInput))
}

@MainActor
@Test
func blocksPasswordField() {
    let fixture = makeSafetyGateFixture()
    let evaluator = fixture.evaluator
    let request = makeRequest(isPasswordLike: true)
    let decision = evaluator.evaluate(request: request, proposedDecision: .rewriteAndMaybeSwitch(replacement: "привет", targetLayout: .russian, reason: "test", confidence: 0.9), isAutoFixEnabled: true)
    #expect(decision == .blocked(.passwordField))
}

@MainActor
@Test
func blocksTerminalContext() {
    let fixture = makeSafetyGateFixture()
    let evaluator = fixture.evaluator
    let request = makeRequest(controlKind: .terminal, isTerminalLike: true)
    let decision = evaluator.evaluate(request: request, proposedDecision: .rewriteAndMaybeSwitch(replacement: "привет", targetLayout: .russian, reason: "test", confidence: 0.9), isAutoFixEnabled: true)
    #expect(decision == .blocked(BlockedReason.terminalLike))
}

@MainActor
@Test
func blocksMissingWritableAxContext() {
    let fixture = makeSafetyGateFixture()
    let evaluator = fixture.evaluator
    let request = makeRequest(supportsWritableAXText: false)
    let decision = evaluator.evaluate(request: request, proposedDecision: .rewriteAndMaybeSwitch(replacement: "привет", targetLayout: .russian, reason: "test", confidence: 0.9), isAutoFixEnabled: true)
    #expect(decision == .blocked(.unsupportedAXContext))
}

@MainActor
@Test
func blocksMissingSelectionRangeForRewrite() {
    let fixture = makeSafetyGateFixture()
    let evaluator = fixture.evaluator
    let request = makeRequest(supportsSelectionRange: false, selectionMode: .lastWord)
    let decision = evaluator.evaluate(request: request, proposedDecision: .rewriteAndMaybeSwitch(replacement: "привет", targetLayout: .russian, reason: "test", confidence: 0.9), isAutoFixEnabled: true)
    #expect(decision == .blocked(BlockedReason.missingSelectionRange))
}

@MainActor
@Test
func blocksRewriteWithoutObservedToken() {
    let fixture = makeSafetyGateFixture()
    let request = makeRequest(observedToken: nil)
    let decision = fixture.evaluator.evaluate(
        request: request,
        proposedDecision: .rewriteAndMaybeSwitch(replacement: "привет", targetLayout: .russian, reason: "test", confidence: 0.9),
        isAutoFixEnabled: true
    )
    #expect(decision == .blocked(.missingObservedToken))
}

@MainActor
@Test
func masterToggleBlocksAutomaticRewrite() {
    let fixture = makeSafetyGateFixture()
    let request = makeRequest(source: .autoWordBoundary)
    let decision = fixture.evaluator.evaluate(
        request: request,
        proposedDecision: .rewriteAndMaybeSwitch(replacement: "привет", targetLayout: .russian, reason: "test", confidence: 0.9),
        isAutoFixEnabled: false
    )
    #expect(decision == .blocked(.autoFixDisabled))
}

@MainActor
@Test
func autoFixPassesForWritableNonSensitiveContextByDefault() {
    let fixture = makeSafetyGateFixture()
    let evaluator = fixture.evaluator
    let request = makeRequest(source: .autoWordBoundary, bundleID: "com.openai.codex", controlKind: .unknown)
    let decision = evaluator.evaluate(request: request, proposedDecision: .rewriteAndMaybeSwitch(replacement: "привет", targetLayout: .russian, reason: "test", confidence: 0.9), isAutoFixEnabled: true)
    guard case .rewriteAndMaybeSwitch = decision else {
        Issue.record("Expected allowed rewrite decision, got \(decision)")
        return
    }
}

@MainActor
@Test
func disabledAppBlocksAutofix() {
    let fixture = IsolatedUserDefaults()
    let store = AppPolicyStore(defaults: fixture.defaults)
    store.upsert(bundleID: "com.openai.codex", displayName: "Codex", mode: .disabled)
    let evaluator = SafetyGateEvaluator(autoFixPolicy: WordBoundaryAutoFixPolicy(appPolicyStore: store))
    let request = makeRequest(source: .autoWordBoundary, bundleID: "com.openai.codex", controlKind: .unknown)
    let decision = evaluator.evaluate(request: request, proposedDecision: .rewriteAndMaybeSwitch(replacement: "привет", targetLayout: .russian, reason: "test", confidence: 0.9), isAutoFixEnabled: true)
    #expect(decision == .blocked(.perAppDisabled))
}

@MainActor
@Test
func fallbackAppModeAllowsAutofixThroughSafetyGate() {
    let fixture = IsolatedUserDefaults()
    let store = AppPolicyStore(defaults: fixture.defaults)
    store.upsert(bundleID: "com.google.Chrome", displayName: "Chrome", mode: .autoFixWithFallback)
    let evaluator = SafetyGateEvaluator(autoFixPolicy: WordBoundaryAutoFixPolicy(appPolicyStore: store))
    let request = makeRequest(source: .autoWordBoundary, bundleID: "com.google.Chrome", controlKind: .browserContentEditable)
    let decision = evaluator.evaluate(request: request, proposedDecision: .rewriteAndMaybeSwitch(replacement: "привет", targetLayout: .russian, reason: "test", confidence: 0.9), isAutoFixEnabled: true)
    guard case .rewriteAndMaybeSwitch = decision else {
        Issue.record("Expected allowed rewrite decision, got \(decision)")
        return
    }
}

@MainActor
@Test
func manualCorrectionCanPassWhenAutofixWouldBeBlocked() {
    let fixture = makeSafetyGateFixture()
    let evaluator = fixture.evaluator
    let request = makeRequest(source: .manualLastWord, bundleID: "com.electron.App", controlKind: .browserTextArea)
    let decision = evaluator.evaluate(request: request, proposedDecision: .rewriteAndMaybeSwitch(replacement: "привет", targetLayout: .russian, reason: "test", confidence: 0.9), isAutoFixEnabled: true)
    guard case .rewriteAndMaybeSwitch = decision else {
        Issue.record("Expected allowed rewrite decision, got \(decision)")
        return
    }
}

@MainActor
private final class SafetyGateTestFixture {
    let isolatedDefaults = IsolatedUserDefaults()
    let evaluator: SafetyGateEvaluator

    init() {
        evaluator = SafetyGateEvaluator(
            autoFixPolicy: WordBoundaryAutoFixPolicy(
                appPolicyStore: AppPolicyStore(defaults: isolatedDefaults.defaults)
            )
        )
    }
}

@MainActor
private func makeSafetyGateFixture() -> SafetyGateTestFixture {
    SafetyGateTestFixture()
}

private func makeRequest(
    source: CorrectionRequest.Source = .manualLastWord,
    observedToken: String? = "ghbdtn",
    bundleID: String = "com.apple.Safari",
    controlKind: AppContext.ControlKind = .browserTextArea,
    isSecureInput: Bool = false,
    isPasswordLike: Bool = false,
    isTerminalLike: Bool = false,
    supportsWritableAXText: Bool = true,
    supportsSelectionRange: Bool = true,
    selectionMode: CorrectionRequest.SelectionMode = .lastWord
) -> CorrectionRequest {
    CorrectionRequest(
        source: source,
        observedToken: observedToken,
        selectionMode: selectionMode,
        context: AppContext(
            frontmostBundleID: bundleID,
            frontmostAppName: "TestApp",
            controlKind: controlKind,
            isSecureInput: isSecureInput,
            isPasswordLike: isPasswordLike,
            isTerminalLike: isTerminalLike,
            supportsWritableAXText: supportsWritableAXText,
            supportsSelectionRange: supportsSelectionRange
        )
    )
}
