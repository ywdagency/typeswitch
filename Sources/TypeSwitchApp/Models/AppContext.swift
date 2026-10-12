import Foundation

struct AppContext: Equatable, Codable {
    enum ControlKind: String, CaseIterable, Codable {
        case nativeTextInput
        case browserTextInput
        case browserTextArea
        case browserContentEditable
        case terminal
        case secureTextField
        case unknown
    }

    var frontmostBundleID: String
    var frontmostAppName: String
    var controlKind: ControlKind
    var isSecureInput: Bool
    var isPasswordLike: Bool
    var isTerminalLike: Bool
    var supportsWritableAXText: Bool
    var supportsSelectionRange: Bool

    var summary: String {
        "\(frontmostAppName) (\(frontmostBundleID)) • \(controlKind.rawValue)"
    }
}
