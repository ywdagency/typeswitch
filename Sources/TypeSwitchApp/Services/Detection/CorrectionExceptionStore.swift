import Foundation

struct CorrectionException: Codable, Equatable, Identifiable {
    let token: String
    let layout: KeyboardLayout
    var id: String { "\(layout.rawValue):\(token)" }
}

struct CorrectionExceptionStore {
    private let defaults: UserDefaults
    private let storageKey = "TypeSwitch.CorrectionExceptions.v1"

    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    func entries() -> [CorrectionException] {
        guard let data = defaults.data(forKey: storageKey),
              let entries = try? JSONDecoder().decode([CorrectionException].self, from: data)
        else { return [] }
        return entries.sorted { $0.id < $1.id }
    }

    func contains(_ token: String, layout: KeyboardLayout) -> Bool {
        entries().contains { $0.layout == layout && $0.token == token.precomposedStringWithCanonicalMapping }
    }

    func add(_ entry: CorrectionException) {
        let token = entry.token.precomposedStringWithCanonicalMapping
        guard (1...64).contains(token.count),
              token.rangeOfCharacter(from: .whitespacesAndNewlines.union(.controlCharacters)) == nil
        else { return }
        let normalized = CorrectionException(token: token, layout: entry.layout)
        save(entries().filter { $0.id != normalized.id } + [normalized])
    }

    func remove(id: String) { save(entries().filter { $0.id != id }) }

    private func save(_ entries: [CorrectionException]) {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        defaults.set(data, forKey: storageKey)
    }
}
