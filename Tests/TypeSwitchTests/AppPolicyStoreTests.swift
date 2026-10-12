import Foundation
import Testing
@testable import TypeSwitchApp

@Test
func appPolicyStoreDefaultsToFallbackAndPersistsOnlyIgnoredApps() {
    let fixture = IsolatedUserDefaults()
    let store = AppPolicyStore(defaults: fixture.defaults)

    #expect(store.mode(for: "com.unknown.App") == .autoFixWithFallback)
    #expect(store.mode(for: "com.unknown.App").allowsSyntheticFallback)

    store.upsert(bundleID: "com.example.App", displayName: "Example", mode: .disabled)
    #expect(store.mode(for: "com.example.App") == .disabled)
    #expect(store.allPolicies().map(\.bundleID) == ["com.example.App"])

    store.setMode(.autoFixWithFallback, for: "com.example.App")
    #expect(store.mode(for: "com.example.App") == .autoFixWithFallback)
    #expect(store.allPolicies().isEmpty)
}

@Test
func appPolicyStorePreservesStoredPolicies() throws {
    let fixture = IsolatedUserDefaults()
    let defaults = fixture.defaults
    let legacyPolicies = [
        AppPolicy(bundleID: "com.google.Chrome", displayName: "Chrome", mode: .autoFixAllowed, isBuiltIn: false),
        AppPolicy(bundleID: "com.example.Disabled", displayName: "Disabled", mode: .disabled, isBuiltIn: false)
    ]
    defaults.set(try JSONEncoder().encode(legacyPolicies), forKey: "TypeSwitch.AppPolicies")

    let store = AppPolicyStore(defaults: defaults)
    #expect(store.mode(for: "com.google.Chrome") == .autoFixWithFallback)
    #expect(store.mode(for: "com.example.Disabled") == .disabled)
    #expect(store.allPolicies().map(\.bundleID) == ["com.example.Disabled"])

    store.setMode(.autoFixWithFallback, for: "com.google.Chrome")
    #expect(store.mode(for: "com.google.Chrome") == .autoFixWithFallback)
}

@Test
func appPolicyStoreMigratesLegacyModesToIgnoredOnly() throws {
    let fixture = IsolatedUserDefaults()
    let defaults = fixture.defaults
    let legacyPolicies = [
        AppPolicy(bundleID: "com.google.Chrome", displayName: "Chrome", mode: .autoFixWithFallback, isBuiltIn: false),
        AppPolicy(bundleID: "com.example.Manual", displayName: "Manual", mode: .manualOnly, isBuiltIn: false),
        AppPolicy(bundleID: "com.example.Disabled", displayName: "Disabled", mode: .disabled, isBuiltIn: false)
    ]
    defaults.set(try JSONEncoder().encode(legacyPolicies), forKey: "TypeSwitch.AppPolicies")
    let store = AppPolicyStore(defaults: defaults)

    #expect(store.allPolicies().map(\.bundleID) == ["com.example.Disabled"])
    #expect(store.mode(for: "com.google.Chrome") == .autoFixWithFallback)
    #expect(store.mode(for: "com.example.Manual") == .autoFixWithFallback)
}

@Test
func appPolicyStoreCanResetAllOverrides() {
    let fixture = IsolatedUserDefaults()
    let store = AppPolicyStore(defaults: fixture.defaults)
    store.upsert(bundleID: "com.example.Disabled", displayName: "Disabled", mode: .disabled)

    store.clearAll()

    #expect(store.allPolicies().isEmpty)
    #expect(store.mode(for: "com.example.Disabled") == .autoFixWithFallback)
}

@Test @MainActor
func coordinatorAddsAnApplicationBundleToIgnoredApps() throws {
    let fixture = IsolatedUserDefaults()
    let defaults = fixture.defaults
    let appURL = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString)
        .appendingPathExtension("app")
    let contentsURL = appURL.appendingPathComponent("Contents")
    try FileManager.default.createDirectory(at: contentsURL, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: appURL) }

    let plist: [String: Any] = [
        "CFBundleIdentifier": "com.example.Ignored",
        "CFBundleName": "Ignored Example"
    ]
    let plistData = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
    try plistData.write(to: contentsURL.appendingPathComponent("Info.plist"))

    let model = AppModel()
    let store = AppPolicyStore(defaults: defaults)
    let coordinator = LayoutCoordinator(
        appModel: model,
        appSettingsStore: AppSettingsStore(defaults: defaults),
        appPolicyStore: store
    )

    #expect(coordinator.addIgnoredApp(at: appURL))
    #expect(model.ignoredApps.map(\.bundleID) == ["com.example.Ignored"])
    #expect(model.ignoredApps.first?.displayName == "Ignored Example")
    #expect(store.mode(for: "com.example.Ignored") == .disabled)
}
