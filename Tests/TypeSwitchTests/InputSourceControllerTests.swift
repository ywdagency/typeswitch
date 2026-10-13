import Foundation
import Testing
@testable import TypeSwitchApp

private final class FakeInputSourceDriver: InputSourceDriving {
    var currentIdentifier: Locked<String?>
    var availableOptions: [InputSourceOption]
    var selectedIdentifiers: Locked<[String]>

    init(currentIdentifier: String?, availableIdentifiers: [String] = [AppConstants.usEnglishSourceID, AppConstants.russianSourceID]) {
        self.currentIdentifier = Locked(currentIdentifier)
        self.availableOptions = availableIdentifiers.map { InputSourceOption(sourceID: $0, displayName: $0) }
        self.selectedIdentifiers = Locked([])
    }

    func currentSourceIdentifier() -> String? {
        currentIdentifier.withLock { $0 }
    }

    func availableSources() -> [InputSourceOption] {
        availableOptions
    }

    func selectSource(identifier: String) -> Bool {
        selectedIdentifiers.withLock { $0.append(identifier) }
        currentIdentifier.withLock { $0 = identifier }
        return true
    }
}

@Test
func readsCurrentLayout() {
    let driver = FakeInputSourceDriver(currentIdentifier: "com.apple.keylayout.Canadian")
    let controller = InputSourceController(driver: driver)
    #expect(controller.currentLayout() == .usEnglish)
}

@Test
func readsUkrainianLayout() {
    let driver = FakeInputSourceDriver(currentIdentifier: "com.apple.keylayout.Ukrainian-PC")
    let controller = InputSourceController(driver: driver)
    #expect(controller.currentLayout() == .ukrainian)
}

@Test
func switchesRequestedLayout() {
    let driver = FakeInputSourceDriver(
        currentIdentifier: "com.apple.keylayout.Canadian",
        availableIdentifiers: ["com.apple.keylayout.Canadian", "com.apple.keylayout.RussianWin"]
    )
    let controller = InputSourceController(driver: driver)
    #expect(controller.switchToLayout(.russian))
    #expect(driver.selectedIdentifiers.withLock(\.last) == "com.apple.keylayout.RussianWin")
}

@Test
func switchesToPreferredInputSourceWhenAvailable() {
    let driver = FakeInputSourceDriver(
        currentIdentifier: "com.apple.keylayout.RussianWin",
        availableIdentifiers: ["com.apple.keylayout.Canadian", AppConstants.usEnglishSourceID]
    )
    let controller = InputSourceController(driver: driver)
    #expect(controller.switchToLayout(.usEnglish, preferredSourceID: "com.apple.keylayout.Canadian"))
    #expect(driver.selectedIdentifiers.withLock(\.last) == "com.apple.keylayout.Canadian")
}

@Test
func switchesToPreferredInputSourceWhenLayoutAlreadyMatchesDifferentSource() {
    let driver = FakeInputSourceDriver(
        currentIdentifier: AppConstants.russianSourceID,
        availableIdentifiers: [AppConstants.russianSourceID, "com.apple.keylayout.RussianWin"]
    )
    let controller = InputSourceController(driver: driver)
    #expect(controller.switchToLayout(.russian, preferredSourceID: "com.apple.keylayout.RussianWin"))
    #expect(driver.selectedIdentifiers.withLock(\.last) == "com.apple.keylayout.RussianWin")
}

@Test
func returnsSortedUniqueAvailableSourceOptions() {
    let driver = FakeInputSourceDriver(
        currentIdentifier: nil,
        availableIdentifiers: ["z.source", "a.source", "z.source"]
    )
    let controller = InputSourceController(driver: driver)
    #expect(controller.availableSourceOptions().map(\.sourceID) == ["a.source", "z.source"])
}

@Test
func noOpsWhenLayoutAlreadyMatches() {
    let driver = FakeInputSourceDriver(currentIdentifier: "com.apple.keylayout.RussianWin")
    let controller = InputSourceController(driver: driver)
    #expect(controller.switchToLayout(.russian))
    #expect(driver.selectedIdentifiers.withLock(\.isEmpty))
}

@Test
func inputSourceOptionHidesTechnicalIdentifier() {
    let localized = InputSourceOption(
        sourceID: "com.apple.keylayout.Canadian",
        displayName: "Canadian"
    )
    let fallback = InputSourceOption(
        sourceID: "com.apple.keylayout.RussianWin",
        displayName: "com.apple.keylayout.RussianWin"
    )

    #expect(localized.userFacingName == "Canadian")
    #expect(fallback.userFacingName == "RussianWin")
}

private final class Locked<Value: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Value

    init(_ value: Value) {
        self.value = value
    }

    func withLock<R>(_ transform: (inout Value) -> R) -> R {
        lock.lock()
        defer { lock.unlock() }
        return transform(&value)
    }
}

@Test
func ownLayoutSwitchDoesNotResetTypingAgainWhenItsNotificationArrives() {
    var changes = InputSourceChangeTracker()
    let sources = [AppConstants.russianSourceID, AppConstants.usEnglishSourceID,
                   AppConstants.usEnglishSourceID, AppConstants.usEnglishSourceID,
                   AppConstants.ukrainianSourceID, AppConstants.russianSourceID]
    // Own selection is recorded before replay; duplicate notifications leave the next word intact.
    let resets = sources.map { changes.observe($0) }
    #expect(resets == [true, true, false, false, true, true])
}

@Test
func unavailableInputSourceStillInvalidatesTypingOnce() {
    var changes = InputSourceChangeTracker()
    let sources: [String?] = [AppConstants.usEnglishSourceID, nil, nil, AppConstants.usEnglishSourceID]
    let resets = sources.map { changes.observe($0) }
    #expect(resets == [true, true, false, true])
}
