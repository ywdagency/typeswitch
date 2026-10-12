import Foundation

struct LayoutMapper {
    private let usToRussian: [Character: Character] = [
        "`": "ё", "~": "Ё", "q": "й", "w": "ц", "e": "у", "r": "к", "t": "е", "y": "н", "u": "г", "i": "ш", "o": "щ", "p": "з",
        "[": "х", "]": "ъ", "a": "ф", "s": "ы", "d": "в", "f": "а", "g": "п", "h": "р", "j": "о", "k": "л",
        "l": "д", ";": "ж", "'": "э", "z": "я", "x": "ч", "c": "с", "v": "м", "b": "и", "n": "т", "m": "ь",
        ",": "б", "<": "Б", ".": "ю", ">": "Ю", "/": ".", "?": ",", ":": "Ж", "\"": "Э", "{": "Х", "}": "Ъ"
    ]

    private let russianToUs: [Character: Character]
    private let usToUkrainian: [Character: Character] = [
        "`": "'", "q": "й", "w": "ц", "e": "у", "r": "к", "t": "е", "y": "н", "u": "г", "i": "ш", "o": "щ", "p": "з",
        "[": "х", "]": "ї", "a": "ф", "s": "і", "d": "в", "f": "а", "g": "п", "h": "р", "j": "о", "k": "л",
        "l": "д", ";": "ж", "'": "є", "z": "я", "x": "ч", "c": "с", "v": "м", "b": "и", "n": "т", "m": "ь",
        ",": "б", ".": "ю", "/": ".", "\\": "ґ"
    ]
    private let ukrainianToUs: [Character: Character]

    init() {
        russianToUs = Dictionary(uniqueKeysWithValues: usToRussian.map { ($1, $0) })
        ukrainianToUs = Dictionary(uniqueKeysWithValues: usToUkrainian.map { ($1, $0) })
    }

    func mapToRussian(_ token: String) -> String {
        map(token, using: usToRussian)
    }

    func mapToEnglish(_ token: String) -> String {
        map(token, using: russianToUs)
    }

    func map(_ token: String, from source: KeyboardLayout, to target: KeyboardLayout) -> String {
        guard source != target else { return token }
        let usToken: String
        switch source {
        case .usEnglish: usToken = token
        case .russian: usToken = map(token, using: russianToUs)
        case .ukrainian: usToken = map(token, using: ukrainianToUs)
        }

        switch target {
        case .usEnglish: return usToken
        case .russian: return map(usToken, using: usToRussian)
        case .ukrainian: return map(usToken, using: usToUkrainian)
        }
    }

    private func map(_ token: String, using mapping: [Character: Character]) -> String {
        String(token.map { character in
            if let mapped = mapping[character] {
                return mapped
            }

            let lower = Character(String(character).lowercased())
            guard let mapped = mapping[lower] else {
                return character
            }

            let mappedString = String(mapped)
            if String(character).uppercased() == String(character), mappedString.rangeOfCharacter(from: .letters) != nil {
                return Character(mappedString.uppercased())
            }

            return mapped
        })
    }
}
