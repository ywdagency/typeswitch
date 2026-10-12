import Foundation

struct AppSettingsStore {
    private enum Key {
        static let autoFixEnabled = "TypeSwitch.Settings.AutoFixEnabled"
        static let soundFeedbackEnabled = "TypeSwitch.Settings.SoundFeedbackEnabled"
        static let diagnosticsEnabled = "TypeSwitch.Settings.DiagnosticsEnabled"
        static let toggleAutoFixHotkey = "TypeSwitch.Settings.ToggleAutoFixHotkey"
        static let englishInputSourceID = "TypeSwitch.Settings.EnglishInputSourceID"
        static let russianInputSourceID = "TypeSwitch.Settings.RussianInputSourceID"
        static let participatingLayouts = "TypeSwitch.Settings.ParticipatingLayouts.v1"
        static let preferredInputSources = "TypeSwitch.Settings.PreferredInputSources.v1"
    }

    private let defaults: UserDefaults
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func autoFixEnabled(defaultValue: Bool = true) -> Bool {
        guard defaults.object(forKey: Key.autoFixEnabled) != nil else {
            return defaultValue
        }
        return defaults.bool(forKey: Key.autoFixEnabled)
    }

    func setAutoFixEnabled(_ enabled: Bool) {
        defaults.set(enabled, forKey: Key.autoFixEnabled)
    }

    func soundFeedbackEnabled(defaultValue: Bool = true) -> Bool {
        guard defaults.object(forKey: Key.soundFeedbackEnabled) != nil else {
            return defaultValue
        }
        return defaults.bool(forKey: Key.soundFeedbackEnabled)
    }

    func setSoundFeedbackEnabled(_ enabled: Bool) {
        defaults.set(enabled, forKey: Key.soundFeedbackEnabled)
    }

    func diagnosticsEnabled(defaultValue: Bool = false) -> Bool {
        guard defaults.object(forKey: Key.diagnosticsEnabled) != nil else {
            return defaultValue
        }
        return defaults.bool(forKey: Key.diagnosticsEnabled)
    }

    func setDiagnosticsEnabled(_ enabled: Bool) {
        defaults.set(enabled, forKey: Key.diagnosticsEnabled)
    }

    func toggleAutoFixHotkey() -> HotkeyShortcut {
        hotkey(forKey: Key.toggleAutoFixHotkey, defaultValue: .defaultToggleAutoFix)
    }

    func setToggleAutoFixHotkey(_ shortcut: HotkeyShortcut) {
        setHotkey(shortcut, forKey: Key.toggleAutoFixHotkey)
    }

    func englishInputSourceID(defaultValue: String = AppConstants.usEnglishSourceID) -> String {
        defaults.string(forKey: Key.englishInputSourceID) ?? defaultValue
    }

    func setEnglishInputSourceID(_ sourceID: String) {
        defaults.set(sourceID, forKey: Key.englishInputSourceID)
    }

    func russianInputSourceID(defaultValue: String = AppConstants.russianSourceID) -> String {
        defaults.string(forKey: Key.russianInputSourceID) ?? defaultValue
    }

    func setRussianInputSourceID(_ sourceID: String) {
        defaults.set(sourceID, forKey: Key.russianInputSourceID)
    }

    func participatingLayouts() -> Set<KeyboardLayout>? {
        guard let values = defaults.array(forKey: Key.participatingLayouts) as? [String] else {
            return nil
        }
        return Set(values.compactMap(KeyboardLayout.init(rawValue:)))
    }

    func setParticipatingLayouts(_ layouts: Set<KeyboardLayout>) {
        defaults.set(layouts.map(\.rawValue).sorted(), forKey: Key.participatingLayouts)
    }

    func preferredInputSourceID(for layout: KeyboardLayout) -> String? {
        (defaults.dictionary(forKey: Key.preferredInputSources) as? [String: String])?[layout.rawValue]
    }

    func setPreferredInputSourceID(_ sourceID: String, for layout: KeyboardLayout) {
        var values = (defaults.dictionary(forKey: Key.preferredInputSources) as? [String: String]) ?? [:]
        values[layout.rawValue] = sourceID
        defaults.set(values, forKey: Key.preferredInputSources)
    }

    private func hotkey(forKey key: String, defaultValue: HotkeyShortcut) -> HotkeyShortcut {
        guard let data = defaults.data(forKey: key),
              let shortcut = try? decoder.decode(HotkeyShortcut.self, from: data)
        else {
            return defaultValue
        }
        return shortcut
    }

    private func setHotkey(_ shortcut: HotkeyShortcut, forKey key: String) {
        guard let data = try? encoder.encode(shortcut) else {
            return
        }
        defaults.set(data, forKey: key)
    }
}
