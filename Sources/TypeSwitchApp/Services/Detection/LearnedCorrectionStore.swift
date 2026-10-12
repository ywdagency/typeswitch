import Foundation

struct LearnedCorrectionStore {
    private let defaults: UserDefaults
    private let storageKey = "TypeSwitch.LearnedCorrections.v1"
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func entries() -> [CorrectionDictionaryEntry] {
        guard let data = defaults.data(forKey: storageKey),
              let entries = try? decoder.decode([CorrectionDictionaryEntry].self, from: data)
        else {
            return []
        }

        return entries.sorted {
            $0.correctToken.localizedCaseInsensitiveCompare($1.correctToken) == .orderedAscending
        }
    }

    func lookup(_ token: String, currentLayout: KeyboardLayout?) -> CorrectionDictionaryEntry? {
        let normalized = Self.normalize(token)
        return entries().first {
            Self.normalize($0.wrongToken) == normalized
                && (currentLayout == nil || $0.sourceLayout == currentLayout)
        }
    }

    func add(_ entry: CorrectionDictionaryEntry) {
        var storedEntries = entries().filter {
            !($0.sourceLayout == entry.sourceLayout
                && Self.normalize($0.wrongToken) == Self.normalize(entry.wrongToken))
        }
        storedEntries.append(entry)
        save(storedEntries)
    }

    func remove(id: String) {
        save(entries().filter { $0.id != id })
    }

    private func save(_ entries: [CorrectionDictionaryEntry]) {
        guard let data = try? encoder.encode(entries) else {
            return
        }
        defaults.set(data, forKey: storageKey)
    }

    private static func normalize(_ token: String) -> String {
        token.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}
