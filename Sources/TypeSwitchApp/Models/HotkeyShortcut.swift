import Carbon
import AppKit
import Foundation

struct HotkeyShortcut: Codable, Equatable {
    enum ModifierPreset: String, CaseIterable, Codable, Identifiable {
        case controlOption
        case controlOptionShift
        case commandOption
        case commandOptionShift

        var id: String { rawValue }

        var label: String {
            switch self {
            case .controlOption:
                "Control + Option"
            case .controlOptionShift:
                "Control + Option + Shift"
            case .commandOption:
                "Command + Option"
            case .commandOptionShift:
                "Command + Option + Shift"
            }
        }

        var carbonFlags: UInt32 {
            switch self {
            case .controlOption:
                UInt32(controlKey | optionKey)
            case .controlOptionShift:
                UInt32(controlKey | optionKey | shiftKey)
            case .commandOption:
                UInt32(cmdKey | optionKey)
            case .commandOptionShift:
                UInt32(cmdKey | optionKey | shiftKey)
            }
        }
    }

    enum Key: String, CaseIterable, Codable, Identifiable {
        case returnKey
        case space
        case tab
        case f13
        case f14
        case f15

        var id: String { rawValue }

        var label: String {
            switch self {
            case .returnKey:
                "Return"
            case .space:
                "Space"
            case .tab:
                "Tab"
            case .f13:
                "F13"
            case .f14:
                "F14"
            case .f15:
                "F15"
            }
        }

        var carbonKeyCode: UInt32 {
            switch self {
            case .returnKey:
                UInt32(kVK_Return)
            case .space:
                UInt32(kVK_Space)
            case .tab:
                UInt32(kVK_Tab)
            case .f13:
                UInt32(kVK_F13)
            case .f14:
                UInt32(kVK_F14)
            case .f15:
                UInt32(kVK_F15)
            }
        }
    }

    var modifiers: ModifierPreset
    var key: Key

    static let defaultToggleAutoFix = HotkeyShortcut(modifiers: .controlOption, key: .space)

    static func captured(keyCode: UInt16, modifierFlags: NSEvent.ModifierFlags) -> HotkeyShortcut? {
        let relevantFlags = modifierFlags.intersection([.control, .option, .shift, .command])
        let modifiers: ModifierPreset

        switch relevantFlags {
        case [.control, .option]:
            modifiers = .controlOption
        case [.control, .option, .shift]:
            modifiers = .controlOptionShift
        case [.command, .option]:
            modifiers = .commandOption
        case [.command, .option, .shift]:
            modifiers = .commandOptionShift
        default:
            return nil
        }

        guard let key = Key.allCases.first(where: { $0.carbonKeyCode == UInt32(keyCode) }) else {
            return nil
        }

        return HotkeyShortcut(modifiers: modifiers, key: key)
    }

    var displayText: String {
        "\(modifiers.label) + \(key.label)"
    }
}
