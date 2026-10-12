import AppKit
import Carbon
import Testing
@testable import TypeSwitchApp

@Test
func capturesSupportedShortcutFromKeyboardEventData() {
    let shortcut = HotkeyShortcut.captured(
        keyCode: UInt16(kVK_Space),
        modifierFlags: [.control, .option]
    )

    #expect(shortcut == .defaultToggleAutoFix)
}

@Test
func refusesUnsupportedShortcutFromKeyboardEventData() {
    #expect(HotkeyShortcut.captured(keyCode: UInt16(kVK_ANSI_A), modifierFlags: [.command]) == nil)
}
