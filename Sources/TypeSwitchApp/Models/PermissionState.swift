import Foundation

struct PermissionState: Equatable {
    enum AccessStatus: String, CaseIterable, Codable {
        case granted
        case missing
        case blocked
        case needsUserAction
        case unknown

        var userFacingLabel: String {
            switch self {
            case .granted:
                "Granted"
            case .missing:
                "Missing"
            case .blocked:
                "Blocked"
            case .needsUserAction:
                "Needs User Action"
            case .unknown:
                "Unknown"
            }
        }
    }

    var inputMonitoring: AccessStatus
    var accessibility: AccessStatus

    static let unknown = PermissionState(inputMonitoring: .unknown, accessibility: .unknown)

    var isReadyForManualCorrection: Bool {
        inputMonitoring == .granted && accessibility == .granted
    }

    var missingPermissionNames: [String] {
        var names: [String] = []
        if inputMonitoring != .granted {
            names.append("Input Monitoring")
        }
        if accessibility != .granted {
            names.append("Accessibility")
        }
        return names
    }

    var missingSummary: String {
        let names = missingPermissionNames
        if names.isEmpty {
            return "All required permissions are granted."
        }
        return "Missing: \(names.joined(separator: ", "))"
    }

    var summary: String {
        "Input Monitoring: \(inputMonitoring.userFacingLabel), Accessibility: \(accessibility.userFacingLabel)"
    }
}
