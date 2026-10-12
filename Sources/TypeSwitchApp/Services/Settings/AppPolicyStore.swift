import Foundation

struct AppPolicyStore {
    static let defaultMode: AppPolicy.Mode = .autoFixWithFallback

    private let defaults: UserDefaults
    private let policiesKey = "TypeSwitch.AppPolicies"
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func allPolicies() -> [AppPolicy] {
        storedPolicies()
            .filter { $0.mode == .disabled }
            .sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
    }

    func mode(for bundleID: String) -> AppPolicy.Mode {
        storedPolicies().contains(where: { $0.bundleID == bundleID && $0.mode == .disabled })
            ? .disabled
            : Self.defaultMode
    }

    func upsert(bundleID: String, displayName: String, mode: AppPolicy.Mode, isBuiltIn: Bool = false) {
        var policies = storedPolicies()
        if mode == Self.defaultMode {
            savePolicies(policies.filter { $0.bundleID != bundleID })
            return
        }

        if let index = policies.firstIndex(where: { $0.bundleID == bundleID }) {
            policies[index].displayName = displayName
            policies[index].mode = mode
            policies[index].isBuiltIn = policies[index].isBuiltIn || isBuiltIn
        } else {
            policies.append(AppPolicy(bundleID: bundleID, displayName: displayName, mode: mode, isBuiltIn: isBuiltIn))
        }

        savePolicies(policies)
    }

    func setMode(_ mode: AppPolicy.Mode, for bundleID: String) {
        var policies = storedPolicies()
        guard let index = policies.firstIndex(where: { $0.bundleID == bundleID }) else {
            return
        }
        if mode == Self.defaultMode {
            policies.remove(at: index)
            savePolicies(policies)
            return
        }
        policies[index].mode = mode
        savePolicies(policies)
    }

    func forget(bundleID: String) {
        let policies = storedPolicies().filter { $0.bundleID != bundleID }
        savePolicies(policies)
    }

    func clearAll() {
        savePolicies([])
    }

    private func storedPolicies() -> [AppPolicy] {
        guard let data = defaults.data(forKey: policiesKey),
              let policies = try? decoder.decode([AppPolicy].self, from: data)
        else {
            return []
        }

        let ignoredApps = policies.filter { $0.mode == .disabled }
        if ignoredApps != policies {
            savePolicies(ignoredApps)
        }
        return ignoredApps
    }

    private func savePolicies(_ policies: [AppPolicy]) {
        guard let data = try? encoder.encode(policies) else {
            return
        }
        defaults.set(data, forKey: policiesKey)
    }

}
