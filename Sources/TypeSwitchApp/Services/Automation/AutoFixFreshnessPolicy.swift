import Foundation

struct AutoFixFreshnessPolicy {
    static func isFresh(scheduledSequence: UInt64, latestSequence: UInt64) -> Bool {
        scheduledSequence == latestSequence
    }
}

struct ObservedTokenLayoutPolicy {
    private static let latinLetters = CharacterSet(
        charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ"
    )
    private static let cyrillicLetters = CharacterSet(
        charactersIn: "абвгдеёжзийклмнопрстуфхцчшщъыьэюяіїєґАБВГДЕЁЖЗИЙКЛМНОПРСТУФХЦЧШЩЪЫЬЭЮЯІЇЄҐ"
    )

    static func isConsistent(_ token: String, with layout: KeyboardLayout) -> Bool {
        switch layout {
        case .usEnglish:
            token.rangeOfCharacter(from: cyrillicLetters) == nil
        case .russian, .ukrainian:
            token.rangeOfCharacter(from: latinLetters) == nil
        }
    }
}
