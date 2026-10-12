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
        targetLayout: KeyboardLayout
    ) -> Bool
}

struct SyntheticTextFallbackRewriteEngine: SyntheticTextFallbackRewriting {
    private let mapper = LayoutMapper()

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
        targetLayout: KeyboardLayout
    ) -> Bool {
        guard let plan = Self.plan(
            observedToken: observedToken,
            replacement: replacement,
            trailingDelimiter: trailingDelimiter
        ) else { return false }

        let physicalText = Self.physicalInsertionText(
            for: plan.insertionText,
            targetLayout: targetLayout,
            mapper: mapper
        )
        let keyStrokes = physicalText.compactMap(keyStroke(for:))
        guard keyStrokes.count == physicalText.count else { return false }

        usleep(40_000)
        for _ in 0..<plan.deleteCount {
            postBackspace()
            usleep(2_000)
        }

        usleep(8_000)
        for keyStroke in keyStrokes {
            postKeyStroke(keyStroke)
            usleep(2_000)
        }
        return true
    }

    private func postBackspace() {
        postKey(virtualKey: CGKeyCode(kVK_Delete), keyDown: true, marked: true)
        postKey(virtualKey: CGKeyCode(kVK_Delete), keyDown: false, marked: true)
    }

    private func postKey(virtualKey: CGKeyCode, keyDown: Bool, marked: Bool) {
        let event = CGEvent(keyboardEventSource: nil, virtualKey: virtualKey, keyDown: keyDown)
        if marked {
            event?.setIntegerValueField(.eventSourceUserData, value: AppConstants.syntheticEventMarker)
        }
        event?.post(tap: .cghidEventTap)
    }

    private func postKeyStroke(_ stroke: KeyStroke) {
        for keyDown in [true, false] {
            guard let event = CGEvent(
                keyboardEventSource: nil,
                virtualKey: stroke.keyCode,
                keyDown: keyDown
            ) else { continue }
            if stroke.requiresShift { event.flags.insert(.maskShift) }
            event.setIntegerValueField(.eventSourceUserData, value: AppConstants.syntheticEventMarker)
            event.post(tap: .cghidEventTap)
        }
    }

    private func keyStroke(for character: Character) -> KeyStroke? {
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
