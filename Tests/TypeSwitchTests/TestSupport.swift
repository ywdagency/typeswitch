import Foundation

final class IsolatedUserDefaults {
    let defaults: UserDefaults

    private let suiteName: String

    init() {
        suiteName = "TypeSwitchTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
    }

    deinit {
        defaults.removePersistentDomain(forName: suiteName)
        defaults.synchronize()
        let preferencesFile = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Preferences", isDirectory: true)
            .appendingPathComponent(suiteName)
            .appendingPathExtension("plist")
        try? FileManager.default.removeItem(at: preferencesFile)
    }
}
