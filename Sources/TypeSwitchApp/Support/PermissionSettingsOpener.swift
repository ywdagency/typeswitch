import AppKit
import Foundation

enum PermissionSettingsOpener {
    static func openSettings(for permission: RequiredPermission) {
        switch permission {
        case .inputMonitoring: openInputMonitoringSettings()
        case .accessibility: openAccessibilitySettings()
        }
    }

    static func revealApplication() {
        NSWorkspace.shared.activateFileViewerSelecting([Bundle.main.bundleURL])
    }

    static func openInputMonitoringSettings() {
        if open("x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent") == false {
            openPrivacyAndSecurity()
        }
    }

    static func openAccessibilitySettings() {
        if open("x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") == false {
            openPrivacyAndSecurity()
        }
    }

    static func openPrivacyAndSecurity() {
        if open("x-apple.systempreferences:com.apple.settings.PrivacySecurity") == false {
            _ = open("x-apple.systempreferences:com.apple.preference.security")
        }
    }

    @discardableResult
    private static func open(_ rawURL: String) -> Bool {
        guard let url = URL(string: rawURL) else {
            return false
        }
        return NSWorkspace.shared.open(url)
    }
}
