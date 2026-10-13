@preconcurrency import ApplicationServices
import CoreGraphics
import Foundation
import IOKit.hidsystem

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
        // Explicitly registers the Input Monitoring request even when AX trust
        // already permits a CoreGraphics event tap.
        IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)
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

    func request(_ permission: RequiredPermission) -> PermissionState {
        var state = refreshState()
        guard state.status(for: permission) != .granted else {
            return state
        }
        switch permission {
        case .inputMonitoring:
            state.inputMonitoring = client.requestInputMonitoring() ? .granted : .needsUserAction
        case .accessibility:
            state.accessibility = client.isAccessibilityTrusted(prompt: true) ? .granted : .needsUserAction
        }
        return state
    }
}
