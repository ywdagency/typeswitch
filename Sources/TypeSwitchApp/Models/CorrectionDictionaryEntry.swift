import Foundation

enum CorrectionDictionaryLanguage: String, CaseIterable, Codable, Identifiable {
    case english
    case russian
    case ukrainian

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .english:
            "English"
        case .russian:
            "Russian"
        case .ukrainian:
            "Ukrainian"
        }
    }
}

enum CorrectionDictionaryLayoutPair: String, Codable, Equatable, CaseIterable, Identifiable {
    case usRussian
    case usUkrainian
    case russianUkrainian

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .usRussian:
            "US/RU"
        case .usUkrainian:
            "US/UA"
        case .russianUkrainian:
            "RU/UA"
        }
    }
}

struct CorrectionDictionaryEntry: Codable, Equatable, Identifiable {
    var id: String { "\(layoutPair.rawValue)|\(wrongToken.lowercased())|\(targetLayout.rawValue)" }

    let wrongToken: String
    let correctToken: String
    let targetLayout: KeyboardLayout
    let sourceLayout: KeyboardLayout
    let layoutPair: CorrectionDictionaryLayoutPair
    let language: CorrectionDictionaryLanguage
    let source: String
}
