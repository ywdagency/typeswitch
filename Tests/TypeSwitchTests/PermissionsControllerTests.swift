import Testing
@testable import TypeSwitchApp

private struct FakePermissionsClient: PermissionsClient {
    var preflightInput = false
    var requestedInput = false
    var trustedAccessibility = false
    var promptedAccessibility = false

    func preflightInputMonitoring() -> Bool { preflightInput }
    func requestInputMonitoring() -> Bool { requestedInput }
    func isAccessibilityTrusted(prompt: Bool) -> Bool {
        prompt ? promptedAccessibility : trustedAccessibility
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
func requestMissingPermissionsPromptsForAccess() {
    let controller = PermissionsController(client: FakePermissionsClient(preflightInput: false, requestedInput: true, trustedAccessibility: false, promptedAccessibility: true))
    let state = controller.requestMissingPermissions(from: .unknown)
    #expect(state.inputMonitoring == .granted)
    #expect(state.accessibility == .granted)
    #expect(state.missingPermissionNames.isEmpty)
    #expect(state.missingSummary == "All required permissions are granted.")
}
