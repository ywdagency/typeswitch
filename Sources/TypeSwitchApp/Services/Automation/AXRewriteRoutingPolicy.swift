import Foundation

enum AXRewriteRoutingPolicy {
    private static let chromiumBundleIDs: Set<String> = [
        "com.google.Chrome",
        "com.google.Chrome.canary"
    ]

    // ChatGPT's composer exposes an AXTextArea that accepts text mutations
    // but can return a stale value immediately afterward. Avoid AX mutation
    // there and use the bounded fallback after the safety gates.
    private static let chatGPTBundleIDs: Set<String> = [
        "com.openai.codex",
        "com.openai.chat"
    ]

    static func requiresBoundedFallback(
        bundleID: String,
        controlKind: AppContext.ControlKind,
        accessibilityRole: String? = nil
    ) -> Bool {
        if chromiumBundleIDs.contains(bundleID) {
            switch controlKind {
            case .browserTextInput, .browserTextArea, .browserContentEditable:
                return true
            case .nativeTextInput, .terminal, .secureTextField, .unknown:
                return false
            }
        }

        return chatGPTBundleIDs.contains(bundleID)
            && controlKind == .nativeTextInput
            && accessibilityRole == "AXTextArea"
    }
}
