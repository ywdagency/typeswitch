import Carbon
import CoreGraphics
import Foundation
import Testing
@testable import TypeSwitchApp

private final class ReplayCharacterResolver: KeyboardCharacterResolving, @unchecked Sendable {
    func characters(keyCode: UInt16, flags: CGEventFlags) -> String? {
        let letters: [UInt16: String] = [37: "l", 14: "e", 17: "t", 1: "s", 0: "a", 11: "b", 8: "c"]
        guard let letter = letters[keyCode] else { return nil }
        return flags.contains(.maskShift) ? letter.uppercased() : letter
    }
}

/// Simulates the tap and a text control without posting events into the user's session.
private final class RewriteEventHarness: @unchecked Sendable {
    private let lock = NSRecursiveLock()
    private var output = ""
    private var forwardedEvents: [CGEvent] = []
    private var postedEvents: [CGEvent] = []
    private var observedEvents: [MonitoredInputEvent] = []
    private var validContext = true
    let queue: RewriteInputQueue
    var monitor: InputMonitor!

    init(text: String = "", capacity: Int = 128, timeoutNanoseconds: UInt64 = 500_000_000,
         undoEscapeGate: CorrectionUndoEscapeGate = CorrectionUndoEscapeGate()) {
        output = text
        queue = RewriteInputQueue(capacity: capacity, timeoutNanoseconds: timeoutNanoseconds)
        monitor = InputMonitor(
            characterResolver: ReplayCharacterResolver(), rewriteInputQueue: queue,
            postEvent: { [weak self] event in self?.locked { self?.postedEvents.append(event) } },
            forwardHeldEvent: { [weak self] event, _ in self?.apply(event) },
            eventHandler: { [weak self] event in self?.locked { self?.observedEvents.append(event) } },
            undoEscapeGate: undoEscapeGate
        )
    }

    func locked<T>(_ operation: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return operation()
    }

    var text: String { locked { output } }
    var forwarded: [CGEvent] { locked { forwardedEvents } }
    var posted: [CGEvent] { locked { postedEvents } }
    var observed: [MonitoredInputEvent] { locked { observedEvents } }
    var contextIsCurrent: Bool {
        get { locked { validContext } }
        set { locked { validContext = newValue } }
    }

    @discardableResult
    func begin(sequence: UInt64? = nil) -> Bool {
        monitor.beginRewrite(expectedSequence: sequence ?? monitor.latestEventSequence()) { [weak self] in
            self?.contextIsCurrent == true
        }
    }

    @discardableResult
    func receive(_ event: CGEvent) -> Bool {
        let passed = monitor.handle(eventType: event.type, event: event) != nil
        if passed { apply(event) }
        return passed
    }

    func apply(_ event: CGEvent) {
        locked {
            forwardedEvents.append(event)
            guard event.type == .keyDown else { return }
            if event.getIntegerValueField(.keyboardEventKeycode) == Int64(kVK_Delete) {
                if !output.isEmpty { output.removeLast() }
            } else {
                output += eventText(event)
            }
        }
    }

    func finish() throws {
        monitor.finishRewrite()
        let completion = try #require(posted.last)
        #expect(RewriteInputQueue.signal(from: completion)?.signal == .completion)
        #expect(receive(completion) == false)
    }

    func waitForObserved(_ count: Int) async throws {
        let deadline = ContinuousClock.now + .seconds(2)
        while observed.count < count, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(1))
        }
        #expect(observed.count == count)
    }
}

private func key(_ code: Int, down: Bool = true, text: String = "", flags: CGEventFlags = [],
                 marker: Int64 = 0) throws -> CGEvent {
    let event = try #require(CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(code), keyDown: down))
    event.flags = flags
    let utf16 = Array(text.utf16)
    utf16.withUnsafeBufferPointer {
        event.keyboardSetUnicodeString(stringLength: $0.count, unicodeString: $0.baseAddress)
    }
    event.setIntegerValueField(.eventSourceUserData, value: marker)
    return event
}

private func eventText(_ event: CGEvent) -> String {
    var count = 0
    event.keyboardGetUnicodeString(maxStringLength: 0, actualStringLength: &count, unicodeString: nil)
    var buffer = [UniChar](repeating: 0, count: max(count, 1))
    event.keyboardGetUnicodeString(maxStringLength: buffer.count, actualStringLength: &count, unicodeString: &buffer)
    return String(decoding: buffer.prefix(count), as: UTF16.self)
}

@Test(arguments: [1, 8, 12])
func fastTypingDuringFallbackIsDeliveredAfterTheCompleteReplacement(pauseNumber: Int) async throws {
    let harness = RewriteEventHarness(text: "руддщ ")
    #expect(harness.begin())
    var rapidEvents: [CGEvent] = []
    for (code, oldText, flags) in [(37, "Д", CGEventFlags.maskShift), (14, "у", []), (17, "е", []), (1, "ы", [])] {
        rapidEvents.append(try key(code, text: oldText, flags: flags))
        rapidEvents.append(try key(code, down: false, text: oldText, flags: flags))
    }
    var pauseCount = 0
    let engine = SyntheticTextFallbackRewriteEngine(
        postEvent: { harness.receive($0) },
        pause: { _ in
            pauseCount += 1
            guard pauseCount == pauseNumber else { return }
            // These payloads were produced before the layout switch. Replay must use physical
            // keys and the new layout, and must preserve Shift on the first letter.
            for event in rapidEvents { #expect(harness.receive(event) == false) }
        }
    )
    #expect(engine.replaceLastToken(observedToken: "руддщ", replacement: "hello", trailingDelimiter: " ",
                                    targetLayout: .usEnglish, canContinue: { harness.monitor.canContinueRewrite() }))
    #expect(harness.text == "hello ")
    // finishRewrite only posts a fence; real keys stay held until the callback sees it.
    harness.monitor.finishRewrite()
    #expect(harness.text == "hello ")
    #expect(harness.receive(try #require(harness.posted.last)) == false)
    #expect(harness.text == "hello Lets")
    #expect(harness.forwarded.suffix(8).map(\.type) == [.keyDown, .keyUp, .keyDown, .keyUp,
                                                       .keyDown, .keyUp, .keyDown, .keyUp])
    try await harness.waitForObserved(4)
    #expect(harness.observed.map(\.event) == [.text("L"), .text("e"), .text("t"), .text("s")])
    #expect(harness.observed.map(\.sequence) == [1, 2, 3, 4])
    #expect(harness.monitor.latestEventSequence() == 4)
}

@Test
func consecutiveRewritesHaveNoInputSuppressionWindow() async throws {
    let harness = RewriteEventHarness()
    for _ in 0..<2 {
        #expect(harness.begin())
        #expect(harness.receive(try key(0, text: "ф")) == false)
        #expect(harness.receive(try key(0, down: false, text: "ф")) == false)
        try harness.finish()
    }
    #expect(harness.receive(try key(11, text: "b")))
    #expect(harness.text == "aab")
    try await harness.waitForObserved(3)
    #expect(harness.observed.map(\.event) == [.text("a"), .text("a"), .text("b")])
    #expect(harness.observed.map(\.sequence) == [1, 2, 3])
}

@Test
func queueCaptureRefusesAlreadyDeliveredTypingAndConcurrentRewrite() throws {
    let harness = RewriteEventHarness()
    #expect(harness.receive(try key(0, text: "a")))
    #expect(harness.begin(sequence: 0) == false)
    #expect(harness.begin(sequence: 1))
    #expect(harness.begin(sequence: 1) == false)
    #expect(harness.receive(try key(11, text: "и")) == false)
    #expect(harness.monitor.latestEventSequence() == 2)
    #expect(AutoFixFreshnessPolicy.isFresh(scheduledSequence: 1, latestSequence: harness.monitor.latestEventSequence()) == false)
    try harness.finish()
}

@Test
func queuePreservesModifiersRepeatBackspaceNavigationAndEscape() async throws {
    let harness = RewriteEventHarness()
    #expect(harness.begin())
    let shift = try key(kVK_Shift, flags: .maskShift)
    shift.type = .flagsChanged
    let repeated = try key(0, text: "ф", flags: .maskShift)
    repeated.setIntegerValueField(.keyboardEventAutorepeat, value: 1)
    let events = [shift, try key(0, text: "ф", flags: .maskShift), repeated,
                  try key(0, down: false, flags: .maskShift), try key(kVK_Delete),
                  try key(kVK_LeftArrow), try key(kVK_Escape), try key(kVK_Escape, down: false)]
    for event in events { #expect(harness.receive(event) == false) }
    try harness.finish()
    #expect(harness.text == "A")
    #expect(harness.forwarded.map(\.type) == events.map(\.type))
    #expect(harness.forwarded[2].getIntegerValueField(.keyboardEventAutorepeat) == 1)
    #expect(harness.forwarded[1].flags == .maskShift)
    try await harness.waitForObserved(5)
    #expect(harness.observed.map(\.event) == [.text("A"), .text("A"), .backspace, .navigation, .escape])
}

@Test
func queueOverflowReleasesKeysInOrderAndCancelsRemainingSyntheticWrites() async throws {
    let harness = RewriteEventHarness(capacity: 2)
    #expect(harness.begin())
    #expect(harness.receive(try key(0, text: "ф")) == false)
    #expect(harness.receive(try key(0, down: false)) == false)
    #expect(harness.receive(try key(11, text: "и")))
    #expect(harness.text == "ab")
    #expect(harness.monitor.canContinueRewrite() == false)
    #expect(harness.receive(try key(kVK_Delete, marker: AppConstants.syntheticEventMarker)) == false)
    #expect(harness.receive(try key(kVK_Delete, down: false, marker: AppConstants.syntheticEventMarker)))
    #expect(harness.begin() == false)
    try harness.finish()
    #expect(harness.text == "ab")
    #expect(harness.begin())
    try harness.finish()
    try await harness.waitForObserved(2)
    #expect(harness.observed.map(\.sequence) == [1, 2])
}

@Test
func timeoutFenceReleasesHeldInputWithoutWaitingForAnotherPhysicalKey() throws {
    let harness = RewriteEventHarness()
    #expect(harness.begin())
    #expect(harness.receive(try key(0, text: "ф")) == false)
    let timeout = try #require(harness.queue.synchronized { harness.queue.session?.timeoutEvent })
    let identifier = try #require(RewriteInputQueue.signal(from: timeout)?.identifier)
    #expect(RewriteInputQueue.signal(from: timeout)?.signal == .timeout)
    #expect(harness.queue.synchronized { harness.queue.session?.identifier } == identifier)
    #expect(harness.receive(timeout) == false)
    #expect(harness.queue.synchronized { harness.queue.session?.aborted } == true)
    #expect(harness.text == "a")
    #expect(harness.monitor.canContinueRewrite() == false)
    #expect(harness.receive(try key(11, text: "b")))
    #expect(harness.receive(try key(kVK_Delete, marker: AppConstants.syntheticEventMarker)) == false)
    try harness.finish()
    #expect(harness.text == "ab")
}

@Test(arguments: [CGEventType.leftMouseDown, .scrollWheel, .tapDisabledByTimeout, .tapDisabledByUserInput])
func contextInterruptionCancelsRewriteBeforeTheInterruptingEvent(type: CGEventType) throws {
    let harness = RewriteEventHarness()
    #expect(harness.begin())
    #expect(harness.receive(try key(0, text: "ф")) == false)
    let interruption = try key(11)
    interruption.type = type
    #expect(harness.receive(interruption))
    #expect(harness.text == "a")
    #expect(harness.forwarded.map(\.type) == [.keyDown, type])
    #expect(harness.monitor.canContinueRewrite() == false)
    try harness.finish()
}

@Test
func commandShortcutCancelsCaptureAfterReleasingEarlierTyping() throws {
    let harness = RewriteEventHarness()
    #expect(harness.begin())
    #expect(harness.receive(try key(0, text: "ф")) == false)
    #expect(harness.receive(try key(8, flags: .maskCommand)))
    #expect(harness.forwarded.map { $0.getIntegerValueField(.keyboardEventKeycode) } == [0, 8])
    #expect(harness.monitor.canContinueRewrite() == false)
    try harness.finish()
}

@Test
func changedOrSecureFocusNeverReceivesPreviouslyHeldTyping() async throws {
    let harness = RewriteEventHarness()
    #expect(harness.begin())
    #expect(harness.receive(try key(0, text: "ф")) == false)
    harness.contextIsCurrent = false
    #expect(harness.receive(try key(kVK_Delete, marker: AppConstants.syntheticEventMarker)) == false)
    try harness.finish()
    #expect(harness.text.isEmpty)
    #expect(harness.forwarded.isEmpty)
    #expect(harness.begin() == false)
    try await harness.waitForObserved(1)
    #expect(harness.observed.allSatisfy { $0.event == .reset })
}

@Test
func staleCompletionAndTimeoutCannotReleaseANewerSession() throws {
    let harness = RewriteEventHarness()
    #expect(harness.begin())
    try harness.finish()
    let oldFence = try #require(harness.posted.last)
    #expect(harness.begin())
    #expect(harness.receive(try key(0, text: "ф")) == false)
    #expect(harness.receive(oldFence) == false)
    let identifier = try #require(RewriteInputQueue.signal(from: oldFence)?.identifier)
    let oldTimeout = try #require(RewriteInputQueue.controlEvent(identifier: identifier, signal: .timeout))
    #expect(harness.receive(oldTimeout) == false)
    #expect(harness.text.isEmpty)
    #expect(harness.monitor.canContinueRewrite())
    try harness.finish()
    #expect(harness.text == "a")
}

@Test
func fallbackRefusesCancellationAndOversizedPlansBeforeDeletingAnything() {
    var posted = 0
    let engine = SyntheticTextFallbackRewriteEngine(postEvent: { _ in posted += 1 }, pause: { _ in })
    #expect(engine.replaceLastToken(observedToken: "руддщ", replacement: "hello", trailingDelimiter: " ",
                                    targetLayout: .usEnglish, canContinue: { false }) == false)
    #expect(engine.replaceLastToken(observedToken: String(repeating: "a", count: 129), replacement: "b",
                                    trailingDelimiter: " ", targetLayout: .usEnglish, canContinue: { true }) == false)
    #expect(posted == 0)
}

@Test
func capturedUndoEscapeReleaseAndRepeatNeverReachTheApplication() throws {
    let gate = CorrectionUndoEscapeGate()
    let harness = RewriteEventHarness(undoEscapeGate: gate)
    gate.arm(expiresAt: .distantFuture) { true }
    #expect(harness.receive(try key(kVK_Escape)) == false)
    #expect(harness.begin())
    #expect(harness.receive(try key(kVK_Escape)) == false)
    #expect(harness.receive(try key(kVK_Escape, down: false)) == false)
    try harness.finish()
    #expect(harness.forwarded.isEmpty)
    #expect(harness.receive(try key(kVK_Escape)))
    #expect(harness.receive(try key(kVK_Escape, down: false)))
}

@Test
func fullQueueReplaysSixtyFourRapidLettersExactlyOnce() async throws {
    let harness = RewriteEventHarness()
    #expect(harness.begin())
    for _ in 0..<16 {
        for (code, oldText, flags) in [(37, "Д", CGEventFlags.maskShift), (14, "у", []), (17, "е", []), (1, "ы", [])] {
            #expect(harness.receive(try key(code, text: oldText, flags: flags)) == false)
            #expect(harness.receive(try key(code, down: false, text: oldText, flags: flags)) == false)
        }
    }
    #expect(harness.queue.synchronized { harness.queue.session?.events.count } == 128)
    #expect(harness.text.isEmpty)
    try harness.finish()
    #expect(harness.text == String(repeating: "Lets", count: 16))
    #expect(harness.forwarded.count == 128)
    try await harness.waitForObserved(64)
    #expect(harness.observed.map(\.sequence) == Array(1...64).map(UInt64.init))
    #expect(harness.monitor.latestEventSequence() == 64)
}

@Test
func queueWatchdogPostsAReleaseSignalWithoutFurtherTyping() async throws {
    let harness = RewriteEventHarness()
    #expect(harness.begin())
    #expect(harness.receive(try key(0, text: "ф")) == false)
    let deadline = ContinuousClock.now + .seconds(2)
    while harness.posted.isEmpty, ContinuousClock.now < deadline {
        try await Task.sleep(for: .milliseconds(1))
    }
    let timeout = try #require(harness.posted.first)
    #expect(RewriteInputQueue.signal(from: timeout)?.signal == .timeout)
    #expect(harness.receive(timeout) == false)
    #expect(harness.text == "a")
    #expect(harness.monitor.canContinueRewrite() == false)
    try harness.finish()
}

@Test
func fallbackStopsDeletingAsSoonAsQueueOverflowCancelsIt() throws {
    let harness = RewriteEventHarness(text: "руддщ ", capacity: 2)
    #expect(harness.begin())
    let typing = [try key(0, text: "ф"), try key(0, down: false), try key(11, text: "b")]
    var didType = false
    var syntheticCount = 0
    let engine = SyntheticTextFallbackRewriteEngine(
        postEvent: { event in syntheticCount += 1; harness.receive(event) },
        pause: { _ in
            if !didType {
                didType = true
                for event in typing { harness.receive(event) }
            }
        }
    )
    #expect(engine.replaceLastToken(observedToken: "руддщ", replacement: "hello", trailingDelimiter: " ",
                                    targetLayout: .usEnglish, canContinue: { harness.monitor.canContinueRewrite() }) == false)
    #expect(syntheticCount == 2)
    try harness.finish()
    #expect(harness.text == "руддщab")
}

@Test
func stoppingMonitoringReleasesCapturedKeysBeforeInvalidatingTheTap() throws {
    let harness = RewriteEventHarness()
    #expect(harness.begin())
    #expect(harness.receive(try key(0, text: "ф")) == false)
    harness.monitor.stop()
    #expect(harness.monitor.canContinueRewrite() == false)
    #expect(harness.text.isEmpty)
    #expect(harness.receive(try #require(harness.posted.last)) == false)
    #expect(harness.text == "a")
    #expect(harness.queue.synchronized { harness.queue.session == nil })
}

@Test
func heldTypingCannotRearmUndoForAnEarlierCorrection() throws {
    let gate = CorrectionUndoEscapeGate()
    let harness = RewriteEventHarness(undoEscapeGate: gate)
    #expect(harness.begin())
    #expect(harness.monitor.armCorrectionUndo(expiresAt: .distantFuture, expectedSequence: 0) { true })
    #expect(harness.receive(try key(0, text: "ф")) == false)
    #expect(harness.monitor.armCorrectionUndo(expiresAt: .distantFuture, expectedSequence: 0) { true } == false)
    #expect(gate.claim() == false)
    try harness.finish()
    #expect(harness.monitor.armCorrectionUndo(expiresAt: .distantFuture, expectedSequence: 1) { true })
    #expect(gate.claim())
}
