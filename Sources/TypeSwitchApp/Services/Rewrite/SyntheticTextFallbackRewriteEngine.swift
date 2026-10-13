import Carbon.HIToolbox
import CoreGraphics
import Darwin
import Foundation

struct SyntheticRewritePlan: Equatable {
    let deleteCount: Int
    let insertionText: String
}

protocol SyntheticTextFallbackRewriting {
    func replaceLastToken(
        observedToken: String,
        replacement: String,
        trailingDelimiter: String,
        targetLayout: KeyboardLayout,
        canContinue: () -> Bool
    ) -> Bool
}

struct SyntheticTextFallbackRewriteEngine: SyntheticTextFallbackRewriting {
    var postEvent: (CGEvent) -> Void = { $0.post(tap: .cghidEventTap) }
    var pause: (UInt32) -> Void = { usleep($0) }

    static func canRecover(after error: Error) -> Bool {
        guard let error = error as? AXElementError else { return false }
        switch error {
        case .missingValue, .missingSelection, .invalidRange, .unsupported:
            return true
        case .notWritable, .staleValue, .verificationFailed:
            return false
        }
    }

    static func plan(
        observedToken: String,
        replacement: String,
        trailingDelimiter: String
    ) -> SyntheticRewritePlan? {
        guard observedToken.isEmpty == false,
              replacement.isEmpty == false,
              trailingDelimiter.count <= 1
        else { return nil }
        return SyntheticRewritePlan(
            deleteCount: observedToken.count + trailingDelimiter.count,
            insertionText: replacement + trailingDelimiter
        )
    }

    static func physicalInsertionText(
        for text: String,
        targetLayout: KeyboardLayout,
        mapper: LayoutMapper = LayoutMapper()
    ) -> String {
        mapper.map(text, from: targetLayout, to: .usEnglish)
    }

    func replaceLastToken(
        observedToken: String,
        replacement: String,
        trailingDelimiter: String,
        targetLayout: KeyboardLayout,
        canContinue: () -> Bool
    ) -> Bool {
        guard let plan = Self.plan(
            observedToken: observedToken,
            replacement: replacement,
            trailingDelimiter: trailingDelimiter
        ) else { return false }

        guard let insertionEvents = Self.insertionEvents(
            for: plan.insertionText,
            targetLayout: targetLayout
        ) else { return false }
        var deletionEvents: [[CGEvent]] = []
        for _ in 0..<plan.deleteCount {
            guard let events = Self.keyEvents(
                keyCode: CGKeyCode(kVK_Delete),
                requiresShift: false,
                text: nil
            ) else { return false }
            deletionEvents.append(events)
        }

        // Keep the operation comfortably inside the input queue's deadline before any deletion.
        guard deletionEvents.count + insertionEvents.count <= 128, canContinue() else { return false }
        for events in deletionEvents {
            guard canContinue() else { return false }
            for event in events { postEvent(event) }
            pause(2_000)
        }

        pause(8_000)
        for events in insertionEvents {
            guard canContinue() else { return false }
            for event in events { postEvent(event) }
            pause(2_000)
        }
        return canContinue()
    }

    static func insertionEvents(for text: String, targetLayout: KeyboardLayout) -> [[CGEvent]]? {
        let physicalText = physicalInsertionText(for: text, targetLayout: targetLayout)
        guard physicalText.count == text.count else { return nil }
        var result: [[CGEvent]] = []
        for (physicalCharacter, insertedCharacter) in zip(physicalText, text) {
            guard let stroke = keyStroke(for: physicalCharacter),
                  let events = keyEvents(
                    keyCode: stroke.keyCode,
                    requiresShift: stroke.requiresShift,
                    text: String(insertedCharacter)
                  )
            else { return nil }
            result.append(events)
        }
        return result
    }

    private static func keyEvents(keyCode: CGKeyCode, requiresShift: Bool, text: String?) -> [CGEvent]? {
        var result: [CGEvent] = []
        for keyDown in [true, false] {
            guard let event = CGEvent(
                keyboardEventSource: nil,
                virtualKey: keyCode,
                keyDown: keyDown
            ) else { return nil }
            // Both the physical modifiers and Unicode payload must describe the intended case.
            event.flags = requiresShift ? .maskShift : []
            if let text {
                let utf16 = Array(text.utf16)
                utf16.withUnsafeBufferPointer { buffer in
                    event.keyboardSetUnicodeString(stringLength: buffer.count, unicodeString: buffer.baseAddress)
                }
            }
            event.setIntegerValueField(.eventSourceUserData, value: AppConstants.syntheticEventMarker)
            result.append(event)
        }
        return result
    }

    private static func keyStroke(for character: Character) -> KeyStroke? {
        let value = String(character)
        let shiftedSymbols: [Character: Character] = [
            "~": "`", "!": "1", "@": "2", "#": "3", "$": "4", "%": "5", "^": "6",
            "&": "7", "*": "8", "(": "9", ")": "0", "_": "-", "+": "=", "{": "[",
            "}": "]", "|": "\\", ":": ";", "\"": "'", "<": ",", ">": ".", "?": "/"
        ]
        let lowercase = Character(value.lowercased())
        let base = shiftedSymbols[character] ?? lowercase
        let requiresShift = shiftedSymbols[character] != nil
            || (value != value.lowercased() && value.rangeOfCharacter(from: .letters) != nil)
        guard let keyCode = Self.keyCodes[base] else { return nil }
        return KeyStroke(keyCode: keyCode, requiresShift: requiresShift)
    }

    private struct KeyStroke {
        let keyCode: CGKeyCode
        let requiresShift: Bool
    }

    private static let keyCodes: [Character: CGKeyCode] = [
        "a": 0, "s": 1, "d": 2, "f": 3, "h": 4, "g": 5, "z": 6, "x": 7,
        "c": 8, "v": 9, "b": 11, "q": 12, "w": 13, "e": 14, "r": 15, "y": 16,
        "t": 17, "1": 18, "2": 19, "3": 20, "4": 21, "6": 22, "5": 23, "=": 24,
        "9": 25, "7": 26, "-": 27, "8": 28, "0": 29, "]": 30, "o": 31, "u": 32,
        "[": 33, "i": 34, "p": 35, "l": 37, "j": 38, "'": 39, "k": 40, ";": 41,
        "\\": 42, ",": 43, "/": 44, "n": 45, "m": 46, ".": 47, "`": 50,
        " ": CGKeyCode(kVK_Space), "\n": CGKeyCode(kVK_Return), "\t": CGKeyCode(kVK_Tab)
    ]
}
