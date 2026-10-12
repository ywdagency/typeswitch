import Foundation

struct AppPolicy: Codable, Equatable, Identifiable {
    enum Mode: String, CaseIterable, Codable, Identifiable {
        case disabled
        case manualOnly
        case autoFixAllowed
        case autoFixWithFallback

        var id: String { rawValue }

        var label: String {
            switch self {
            case .disabled:
                "Disabled"
            case .manualOnly:
                "Manual Only"
            case .autoFixAllowed:
                "Auto-Fix"
            case .autoFixWithFallback:
                "Auto-Fix + Fallback"
            }
        }

        var allowsAutoFix: Bool {
            self == .autoFixAllowed || self == .autoFixWithFallback
        }

        var allowsSyntheticFallback: Bool {
            self == .autoFixWithFallback
        }
    }

    var id: String { bundleID }
    let bundleID: String
    var displayName: String
    var mode: Mode
    var isBuiltIn: Bool
}
