import Carbon
import CoreGraphics
import Testing
@testable import TypeSwitchApp

private struct FakeKeyboardCharacterResolver: KeyboardCharacterResolving {
    let value: String?
    func characters(keyCode: UInt16, flags: CGEventFlags) -> String? { value }
}

private final class RefreshTrackingKeyboardCharacterResolver: KeyboardCharacterResolving, @unchecked Sendable {
    private let lock = NSLock()
    private var refreshes = 0

    var refreshCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return refreshes
    }

    @MainActor
    func refreshLayout() {
        lock.lock()
        refreshes += 1
        lock.unlock()
    }

    func characters(keyCode: UInt16, flags: CGEventFlags) -> String? { nil }
}

@Test
func inputEventSequenceClockAdvancesInDeliveryOrder() {
    let clock = InputEventSequenceClock()

    #expect(clock.current() == 0)
    #expect(clock.advance() == 1)
    #expect(clock.advance() == 2)
    #expect(clock.current() == 2)
}

@Test
func ignoresModifierShortcuts() {
    let normalizer = InputEventNormalizer()
    #expect(normalizer.normalize(keyCode: UInt16(kVK_ANSI_A), characters: "a", flags: [.maskCommand]) == nil)
}

@Test
func normalizesPasteShortcut() {
    let normalizer = InputEventNormalizer()
    #expect(normalizer.normalize(keyCode: UInt16(kVK_ANSI_V), characters: "v", flags: [.maskCommand]) == .paste)
}

@Test
func normalizesBackspace() {
    let normalizer = InputEventNormalizer()
    #expect(normalizer.normalize(keyCode: UInt16(kVK_Delete), characters: nil, flags: []) == .backspace)
}

@Test
func normalizesDelimiter() {
    let normalizer = InputEventNormalizer()
    #expect(normalizer.normalize(keyCode: UInt16(kVK_Space), characters: " ", flags: []) == .delimiter(" "))
}

@Test
func normalizesWrongLayoutLetterPunctuationAsText() {
    let normalizer = InputEventNormalizer()
    #expect(normalizer.normalize(keyCode: UInt16(kVK_ANSI_LeftBracket), characters: "[", flags: []) == .text("["))
    #expect(normalizer.normalize(keyCode: UInt16(kVK_ANSI_Period), characters: ".", flags: []) == .text("."))
    #expect(normalizer.normalize(keyCode: UInt16(kVK_ANSI_Comma), characters: ",", flags: []) == .text(","))
    #expect(normalizer.normalize(keyCode: UInt16(kVK_ANSI_Semicolon), characters: ";", flags: []) == .text(";"))
    #expect(normalizer.normalize(keyCode: UInt16(kVK_ANSI_Quote), characters: "'", flags: []) == .text("'"))
}

@Test
func normalizesText() {
    let normalizer = InputEventNormalizer()
    #expect(normalizer.normalize(keyCode: UInt16(kVK_ANSI_G), characters: "g", flags: []) == .text("g"))
}

@Test
func syntheticInputSuppressionUsesMarkerAndBoundedGraceWindow() {
    let gate = SyntheticInputSuppressionGate()
    let marker: Int64 = 123

    #expect(gate.shouldSuppress(eventMarker: marker, syntheticMarker: marker, now: 10_000))
    #expect(gate.shouldSuppress(eventMarker: 0, syntheticMarker: marker, now: 10_000) == false)

    gate.suppress(forNanoseconds: 250, now: 10_000)

    #expect(gate.shouldSuppress(eventMarker: 0, syntheticMarker: marker, now: 10_249))
    #expect(gate.shouldSuppress(eventMarker: 0, syntheticMarker: marker, now: 10_250) == false)
}

@Test
func inputMonitorPrefersCurrentLayoutTranslationOverEventFallback() {
    let monitor = InputMonitor(characterResolver: FakeKeyboardCharacterResolver(value: "і"))
    #expect(monitor.normalizedEvent(
        keyCode: UInt16(kVK_ANSI_S),
        fallbackCharacters: "s",
        flags: []
    ) == .text("і"))
}

@Test
func inputMonitorFallsBackWhenLayoutDataIsUnavailable() {
    let monitor = InputMonitor(characterResolver: FakeKeyboardCharacterResolver(value: nil))
    #expect(monitor.normalizedEvent(
        keyCode: UInt16(kVK_ANSI_S),
        fallbackCharacters: "s",
        flags: []
    ) == .text("s"))
}

@MainActor
@Test
func inputMonitorRefreshesKeyboardSnapshotOnMainActor() {
    let resolver = RefreshTrackingKeyboardCharacterResolver()
    let monitor = InputMonitor(characterResolver: resolver)

    monitor.refreshKeyboardLayout()

    #expect(resolver.refreshCount == 1)
}

@MainActor
@Test
func cachedSystemKeyboardSnapshotCanBeReadOffMainThread() async {
    let resolver = SystemKeyboardCharacterResolver()
    resolver.refreshLayout()

    let characters = await Task.detached {
        resolver.characters(keyCode: UInt16(kVK_ANSI_A), flags: [])
    }.value

    #expect(characters?.isEmpty == false)
}
