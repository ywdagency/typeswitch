import Testing
@testable import TypeSwitchApp

private final class FakePermissionsClient: PermissionsClient {
    var preflightInput = false
    var requestedInput = false
    var trustedAccessibility = false
    var promptedAccessibility = false
    var inputRequests = 0
    var accessibilityRequests = 0

    init(preflightInput: Bool = false, requestedInput: Bool = false, trustedAccessibility: Bool = false, promptedAccessibility: Bool = false) {
        self.preflightInput = preflightInput
        self.requestedInput = requestedInput
        self.trustedAccessibility = trustedAccessibility
        self.promptedAccessibility = promptedAccessibility
    }

    func preflightInputMonitoring() -> Bool { preflightInput }
    func requestInputMonitoring() -> Bool {
        inputRequests += 1
        return requestedInput
    }
    func isAccessibilityTrusted(prompt: Bool) -> Bool {
        if prompt {
            accessibilityRequests += 1
            return promptedAccessibility
        }
        return trustedAccessibility
    }
}

@MainActor
@Test
func refreshStateReflectsClientStatus() {
    let controller = PermissionsController(client: FakePermissionsClient(preflightInput: true, requestedInput: false, trustedAccessibility: false, promptedAccessibility: false))
    let state = controller.refreshState()
    #expect(state.inputMonitoring == .granted)
    #expect(state.accessibility == .missing)
    #expect(state.missingPermissionNames == ["Accessibility"])
    #expect(state.missingSummary == "Missing: Accessibility")
}

@MainActor
@Test
func inputMonitoringRequestDoesNotPromptForAccessibility() {
    let client = FakePermissionsClient(requestedInput: true)
    let controller = PermissionsController(client: client)
    let state = controller.request(.inputMonitoring)
    #expect(state.inputMonitoring == .granted)
    #expect(state.accessibility == .missing)
    #expect(client.inputRequests == 1)
    #expect(client.accessibilityRequests == 0)
}

@MainActor
@Test
func accessibilityRequestDoesNotPromptForInputMonitoring() {
    let client = FakePermissionsClient(promptedAccessibility: true)
    let state = PermissionsController(client: client).request(.accessibility)
    #expect(state.accessibility == .granted)
    #expect(state.inputMonitoring == .missing)
    #expect(client.inputRequests == 0)
    #expect(client.accessibilityRequests == 1)
}

@MainActor
@Test
func deniedRequestRemainsUnavailableUntilSystemConfirmsGrant() {
    let client = FakePermissionsClient(trustedAccessibility: true)
    let controller = PermissionsController(client: client)
    #expect(controller.request(.inputMonitoring).inputMonitoring == .needsUserAction)
    #expect(controller.refreshState().isReadyForManualCorrection == false)
    client.preflightInput = true
    #expect(controller.refreshState().isReadyForManualCorrection)
    #expect(client.inputRequests == 1)
    #expect(client.accessibilityRequests == 0)
}

@MainActor
@Test
func alreadyGrantedPermissionsDoNotPromptAgainAndRevocationIsDetected() {
    let client = FakePermissionsClient(preflightInput: true, trustedAccessibility: true)
    let controller = PermissionsController(client: client)
    #expect(controller.request(.inputMonitoring).isReadyForManualCorrection)
    #expect(controller.request(.accessibility).isReadyForManualCorrection)
    #expect(client.inputRequests == 0)
    #expect(client.accessibilityRequests == 0)
    client.trustedAccessibility = false
    #expect(controller.refreshState().isReadyForManualCorrection == false)
    #expect(controller.request(.accessibility).accessibility == .needsUserAction)
    #expect(client.accessibilityRequests == 1)
}
