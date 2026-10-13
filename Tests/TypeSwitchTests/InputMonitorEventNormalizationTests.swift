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
func normalizesEscapeWithoutTreatingItAsTextOrBackspace() {
    let normalizer = InputEventNormalizer()
    #expect(normalizer.normalize(keyCode: UInt16(kVK_Escape), characters: "\u{1b}", flags: []) == .escape)
    #expect(normalizer.normalize(keyCode: UInt16(kVK_Escape), characters: nil, flags: .maskAlphaShift) == .escape)
    #expect(normalizer.normalize(keyCode: UInt16(kVK_Escape), characters: nil, flags: .maskShift) == .reset)
    #expect(normalizer.normalize(keyCode: UInt16(kVK_Escape), characters: nil, flags: .maskCommand) == nil)
}

@Test
func eventFilterConsumesOnlyEligibleEscapeIncludingReleaseAndRepeat() throws {
    let gate = CorrectionUndoEscapeGate()
    let monitor = InputMonitor(characterResolver: FakeKeyboardCharacterResolver(value: nil), undoEscapeGate: gate)
    let down = try #require(CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(kVK_Escape), keyDown: true))
    let up = try #require(CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(kVK_Escape), keyDown: false))
    down.flags = []
    up.flags = []
    #expect(monitor.handle(eventType: .keyDown, event: down) != nil)
    gate.arm(expiresAt: .distantFuture) { true }
    #expect(monitor.handle(eventType: .keyDown, event: down) == nil)
    #expect(monitor.handle(eventType: .keyDown, event: down) == nil)
    #expect(monitor.handle(eventType: .keyUp, event: up) == nil)
    #expect(monitor.handle(eventType: .keyDown, event: down) != nil)
    #expect(monitor.handle(eventType: .keyUp, event: up) != nil)
}

@Test
func eventFilterPassesModifiedEscapeAndInvalidatesUndoOnRealInput() throws {
    let gate = CorrectionUndoEscapeGate()
    let monitor = InputMonitor(characterResolver: FakeKeyboardCharacterResolver(value: nil), undoEscapeGate: gate)
    let escape = try #require(CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(kVK_Escape), keyDown: true))
    for modifier in [CGEventFlags.maskShift, .maskAlternate, .maskCommand, .maskControl] {
        gate.arm(expiresAt: .distantFuture) { true }
        escape.flags = modifier
        #expect(monitor.handle(eventType: .keyDown, event: escape) != nil)
        #expect(gate.claim() == false)
    }
    let backspace = try #require(CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(kVK_Delete), keyDown: true))
    backspace.flags = []
    gate.arm(expiresAt: .distantFuture) { true }
    #expect(monitor.handle(eventType: .keyDown, event: backspace) != nil)
    #expect(gate.claim() == false)
    for type in [CGEventType.leftMouseDown, .rightMouseDown, .scrollWheel, .tapDisabledByTimeout] {
        gate.arm(expiresAt: .distantFuture) { true }
        #expect(monitor.handle(eventType: type, event: backspace) != nil)
        #expect(gate.claim() == false)
    }
}

@Test
func markedSyntheticEventsDoNotCancelUndoAndEscapeWorksImmediately() throws {
    let gate = CorrectionUndoEscapeGate()
    let monitor = InputMonitor(characterResolver: FakeKeyboardCharacterResolver(value: nil), undoEscapeGate: gate)
    let synthetic = try #require(CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(kVK_ANSI_A), keyDown: true))
    synthetic.setIntegerValueField(.eventSourceUserData, value: AppConstants.syntheticEventMarker)
    gate.arm(expiresAt: .distantFuture) { true }
    #expect(monitor.handle(eventType: .keyDown, event: synthetic) != nil)
    #expect(monitor.latestEventSequence() == 0)
    let escape = try #require(CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(kVK_Escape), keyDown: true))
    escape.flags = []
    #expect(monitor.handle(eventType: .keyDown, event: escape) == nil)
    #expect(monitor.latestEventSequence() == 1)
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
