@preconcurrency import ApplicationServices
import CoreGraphics
import Foundation

protocol PermissionsClient {
    func preflightInputMonitoring() -> Bool
    func requestInputMonitoring() -> Bool
    func isAccessibilityTrusted(prompt: Bool) -> Bool
}

struct SystemPermissionsClient: PermissionsClient {
    func preflightInputMonitoring() -> Bool {
        CGPreflightListenEventAccess()
    }

    func requestInputMonitoring() -> Bool {
        CGRequestListenEventAccess()
    }

    func isAccessibilityTrusted(prompt: Bool) -> Bool {
        if prompt {
            return AXIsProcessTrustedWithOptions([
                kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true
            ] as CFDictionary)
        }

        return AXIsProcessTrusted()
    }
}

@MainActor
final class PermissionsController {
    private let client: PermissionsClient

    init(client: PermissionsClient = SystemPermissionsClient()) {
        self.client = client
    }

    func refreshState() -> PermissionState {
        PermissionState(
            inputMonitoring: client.preflightInputMonitoring() ? .granted : .missing,
            accessibility: client.isAccessibilityTrusted(prompt: false) ? .granted : .missing
        )
    }

    func requestMissingPermissions(from currentState: PermissionState) -> PermissionState {
        let inputMonitoringStatus: PermissionState.AccessStatus
        if currentState.inputMonitoring == .granted || client.preflightInputMonitoring() {
            inputMonitoringStatus = .granted
        } else {
            inputMonitoringStatus = client.requestInputMonitoring() ? .granted : .needsUserAction
        }

        let accessibilityStatus: PermissionState.AccessStatus
        if currentState.accessibility == .granted || client.isAccessibilityTrusted(prompt: false) {
            accessibilityStatus = .granted
        } else {
            accessibilityStatus = client.isAccessibilityTrusted(prompt: true) ? .granted : .needsUserAction
        }

        return PermissionState(inputMonitoring: inputMonitoringStatus, accessibility: accessibilityStatus)
    }
}
