import Testing
@testable import TypeSwitchApp

@Test
func appSettingsStorePersistsTogglesAndHotkeys() {
    let fixture = IsolatedUserDefaults()
    let store = AppSettingsStore(defaults: fixture.defaults)

    #expect(store.autoFixEnabled())
    #expect(store.soundFeedbackEnabled())
    #expect(store.diagnosticsEnabled() == false)
    #expect(store.toggleAutoFixHotkey() == .defaultToggleAutoFix)

    store.setAutoFixEnabled(false)
    store.setSoundFeedbackEnabled(false)
    store.setDiagnosticsEnabled(true)

    let custom = HotkeyShortcut(modifiers: .commandOption, key: .space)
    store.setToggleAutoFixHotkey(custom)
    store.setEnglishInputSourceID("com.apple.keylayout.Canadian")
    store.setRussianInputSourceID("com.apple.keylayout.RussianWin")
    store.setParticipatingLayouts([.usEnglish, .ukrainian])
    store.setPreferredInputSourceID("com.apple.keylayout.Ukrainian-PC", for: .ukrainian)

    #expect(store.autoFixEnabled() == false)
    #expect(store.soundFeedbackEnabled() == false)
    #expect(store.diagnosticsEnabled())
    #expect(store.toggleAutoFixHotkey() == custom)
    #expect(store.englishInputSourceID() == "com.apple.keylayout.Canadian")
    #expect(store.russianInputSourceID() == "com.apple.keylayout.RussianWin")
    #expect(store.participatingLayouts() == [.usEnglish, .ukrainian])
    #expect(store.preferredInputSourceID(for: .ukrainian) == "com.apple.keylayout.Ukrainian-PC")
}
