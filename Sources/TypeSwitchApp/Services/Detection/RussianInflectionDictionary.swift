import Foundation

/// Recognizes one suffix transformation explicitly licensed by a bundled Hunspell entry.
/// It never guesses a declension from a word's ending or chains transformations.
struct RussianInflectionDictionary: Sendable {
    private static let letters = CharacterSet(charactersIn: "абвгдеёжзийклмнопрстуфхцчшщъыьэюя")

    private let flagsByBase: [String: Set<Character>]
    private let rulesByEnding: [String: [SuffixRule]]
    private let maximumEndingLength: Int

    init(baseLines: [String] = [], ruleLines: [String] = []) {
        var flagsByBase: [String: Set<Character>] = [:]
        for line in baseLines {
            let fields = line.split(separator: "\t")
            guard fields.count == 2 else { continue }
            flagsByBase[String(fields[0]), default: []].formUnion(fields[1])
        }

        var rulesByEnding: [String: [SuffixRule]] = [:]
        for line in ruleLines {
            let fields = line.split(separator: "\t")
            guard fields.count == 4, fields[0].count == 1,
                  let flag = fields[0].first,
                  let condition = try? NSRegularExpression(pattern: "(?:\(fields[3]))$")
            else { continue }

            let ending = fields[2] == "0" ? "" : String(fields[2])
            let rule = SuffixRule(
                flag: flag,
                strippedEnding: fields[1] == "0" ? "" : String(fields[1]),
                condition: condition
            )
            rulesByEnding[ending, default: []].append(rule)
        }

        self.flagsByBase = flagsByBase
        self.rulesByEnding = rulesByEnding
        self.maximumEndingLength = rulesByEnding.keys.map(\.count).max() ?? 0
    }

    func contains(_ word: String) -> Bool {
        guard (2...48).contains(word.count),
              word.unicodeScalars.allSatisfy({ Self.letters.contains($0) })
        else { return false }

        // Reverse the suffix, then verify both the original entry's flag and the
        // rule's condition against that entry. The resulting form stays unchanged.
        for length in 0...min(maximumEndingLength, word.count) {
            let ending = String(word.suffix(length))
            guard let rules = rulesByEnding[ending] else { continue }
            let stem = String(word.dropLast(length))
            for rule in rules {
                let base = stem + rule.strippedEnding
                guard flagsByBase[base]?.contains(rule.flag) == true else { continue }
                if rule.condition.firstMatch(in: base, range: NSRange(base.startIndex..., in: base)) != nil {
                    return true
                }
            }
        }
        return false
    }

    private struct SuffixRule: Sendable {
        let flag: Character
        let strippedEnding: String
        let condition: NSRegularExpression
    }
}
