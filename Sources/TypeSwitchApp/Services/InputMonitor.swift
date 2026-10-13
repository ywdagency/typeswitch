import Carbon
import CoreGraphics
import Foundation

enum InputMonitorStatus: String, Sendable {
    case eventTapCreated
    case eventTapCreationFailed
    case firstKeyDownObserved
}

protocol KeyboardCharacterResolving {
    @MainActor func refreshLayout()
    func characters(keyCode: UInt16, flags: CGEventFlags) -> String?
}

extension KeyboardCharacterResolving {
    @MainActor func refreshLayout() {}
}

final class InputEventSequenceClock: @unchecked Sendable {
    private let lock = NSLock()
    private var sequence: UInt64 = 0

    func advance() -> UInt64 {
        lock.lock()
        defer { lock.unlock() }
        sequence &+= 1
        return sequence
    }

    func current() -> UInt64 {
        lock.lock()
        defer { lock.unlock() }
        return sequence
    }
}

private struct KeyboardLayoutSnapshot {
    let data: Data
    let keyboardType: UInt32
}

final class SystemKeyboardCharacterResolver: KeyboardCharacterResolving, @unchecked Sendable {
    private let lock = NSLock()
    private var snapshot: KeyboardLayoutSnapshot?

    @MainActor
    func refreshLayout() {
        guard let inputSource = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
              let rawData = TISGetInputSourceProperty(inputSource, kTISPropertyUnicodeKeyLayoutData)
        else {
            replaceSnapshot(nil)
            return
        }

        let layoutData = Unmanaged<CFData>.fromOpaque(rawData).takeUnretainedValue()
        guard let bytes = CFDataGetBytePtr(layoutData) else {
            replaceSnapshot(nil)
            return
        }
        replaceSnapshot(
            KeyboardLayoutSnapshot(
                data: Data(bytes: bytes, count: CFDataGetLength(layoutData)),
                keyboardType: UInt32(LMGetKbdType())
            )
        )
    }

    func characters(keyCode: UInt16, flags: CGEventFlags) -> String? {
        guard let snapshot = currentSnapshot() else { return nil }

        var carbonModifiers: UInt32 = 0
        if flags.contains(.maskShift) { carbonModifiers |= UInt32(shiftKey) }
        if flags.contains(.maskAlphaShift) { carbonModifiers |= UInt32(alphaLock) }
        if flags.contains(.maskAlternate) { carbonModifiers |= UInt32(optionKey) }

        return snapshot.data.withUnsafeBytes { rawBuffer -> String? in
            guard let baseAddress = rawBuffer.baseAddress else { return nil }
            let keyboardLayout = baseAddress.assumingMemoryBound(to: UCKeyboardLayout.self)
            var deadKeyState: UInt32 = 0
            var actualLength = 0
            var buffer = Array(repeating: UniChar(0), count: 8)
            let status = UCKeyTranslate(
                keyboardLayout,
                keyCode,
                UInt16(kUCKeyActionDown),
                (carbonModifiers >> 8) & 0xFF,
                snapshot.keyboardType,
                OptionBits(kUCKeyTranslateNoDeadKeysBit),
                &deadKeyState,
                buffer.count,
                &actualLength,
                &buffer
            )
            guard status == noErr, actualLength > 0 else { return nil }
            return String(utf16CodeUnits: buffer, count: actualLength)
        }
    }

    private func currentSnapshot() -> KeyboardLayoutSnapshot? {
        lock.lock()
        defer { lock.unlock() }
        return snapshot
    }

    private func replaceSnapshot(_ snapshot: KeyboardLayoutSnapshot?) {
        lock.lock()
        self.snapshot = snapshot
        lock.unlock()
    }
}

struct InputEventNormalizer {
    func normalize(keyCode: UInt16, characters: String?, flags: CGEventFlags) -> NormalizedInputEvent? {
        if flags.contains(.maskCommand) || flags.contains(.maskControl) {
            if flags.contains(.maskCommand), keyCode == UInt16(kVK_ANSI_V) {
                return .paste
            }
            return nil
        }

        switch Int(keyCode) {
        case kVK_Escape:
            return flags.intersection([.maskShift, .maskAlternate]).isEmpty ? .escape : .reset
        case kVK_Delete:
            return .backspace
        case kVK_LeftArrow, kVK_RightArrow, kVK_UpArrow, kVK_DownArrow, kVK_Home, kVK_End, kVK_PageUp, kVK_PageDown:
            return .navigation
        default:
            break
        }

        guard let characters, characters.isEmpty == false else {
            return nil
        }

        if characters.count > 1 {
            return nil
        }

        guard let character = characters.first else {
            return nil
        }

        if BufferManager.isWordBoundary(character) {
            return .delimiter(character)
        }

        return .text(String(character))
    }
}

final class InputMonitor: @unchecked Sendable {
    typealias EventHandler = @Sendable (MonitoredInputEvent) -> Void

    private let normalizer: InputEventNormalizer
    private let characterResolver: KeyboardCharacterResolving
    private let rewriteInputQueue: RewriteInputQueue
    private let postEvent: @Sendable (CGEvent) -> Void
    private let forwardHeldEvent: @Sendable (CGEvent, CGEventTapProxy?) -> Void
    private let eventSequenceClock: InputEventSequenceClock
    private let undoEscapeGate: CorrectionUndoEscapeGate
    private let processingQueue = DispatchQueue(label: AppConstants.inputMonitorQueueLabel)
    private let firstKeyEventLock = NSLock()
    private var didReportFirstKeyEvent = false
    private var eventHandler: EventHandler?
    private var statusHandler: (@Sendable (InputMonitorStatus) -> Void)?
    private var eventTap: CFMachPort?
    private var runLoop: CFRunLoop?
    private var tapThread: Thread?
    private var consumingEscape = false
    private var stopAfterRewrite = false

    init(
        normalizer: InputEventNormalizer = InputEventNormalizer(),
        characterResolver: KeyboardCharacterResolving = SystemKeyboardCharacterResolver(),
        rewriteInputQueue: RewriteInputQueue = RewriteInputQueue(),
        postEvent: @escaping @Sendable (CGEvent) -> Void = { $0.post(tap: .cghidEventTap) },
        forwardHeldEvent: @escaping @Sendable (CGEvent, CGEventTapProxy?) -> Void = { $0.tapPostEvent($1) },
        eventHandler: EventHandler? = nil,
        eventSequenceClock: InputEventSequenceClock = InputEventSequenceClock(),
        undoEscapeGate: CorrectionUndoEscapeGate = CorrectionUndoEscapeGate()
    ) {
        self.normalizer = normalizer
        self.characterResolver = characterResolver
        self.rewriteInputQueue = rewriteInputQueue
        self.postEvent = postEvent
        self.forwardHeldEvent = forwardHeldEvent
        self.eventHandler = eventHandler
        self.eventSequenceClock = eventSequenceClock
        self.undoEscapeGate = undoEscapeGate
    }

    @MainActor
    func start(
        eventHandler: @escaping EventHandler,
        statusHandler: @escaping @Sendable (InputMonitorStatus) -> Void = { _ in }
    ) {
        characterResolver.refreshLayout()
        guard tapThread == nil else {
            self.eventHandler = eventHandler
            self.statusHandler = statusHandler
            return
        }

        self.eventHandler = eventHandler
        self.statusHandler = statusHandler
        let thread = Thread { [weak self] in
            self?.runEventTapLoop()
        }
        thread.name = "TypeSwitch.InputMonitor"
        tapThread = thread
        thread.start()
    }

    @MainActor
    func refreshKeyboardLayout() {
        characterResolver.refreshLayout()
    }

    func stop() {
        rewriteInputQueue.synchronized {
            undoEscapeGate.invalidate()
            eventHandler = nil
            if let session = rewriteInputQueue.session {
                session.aborted = true
                stopAfterRewrite = true
                if !session.finishing {
                    session.finishing = true
                    postEvent(session.completionEvent)
                }
                return
            }
            stopEventTap()
        }
    }

    private func stopEventTap() {
        if let eventTap { CFMachPortInvalidate(eventTap) }
        if let runLoop { CFRunLoopStop(runLoop) }
        eventTap = nil
        runLoop = nil
        tapThread = nil
        stopAfterRewrite = false
        consumingEscape = false
    }

    /// The freshness check and capture start share the same lock as ordinary event delivery.
    func beginRewrite(expectedSequence: UInt64, isContextCurrent: @escaping @Sendable () -> Bool) -> Bool {
        rewriteInputQueue.synchronized {
            guard eventSequenceClock.current() == expectedSequence,
                  let session = rewriteInputQueue.begin(
                    now: DispatchTime.now().uptimeNanoseconds, isContextCurrent: isContextCurrent
                  )
            else { return false }
            let identifier = session.identifier
            processingQueue.asyncAfter(deadline: .now() + .nanoseconds(Int(rewriteInputQueue.timeoutNanoseconds))) { [weak self] in
                guard let self else { return }
                self.rewriteInputQueue.synchronized {
                    guard let current = self.rewriteInputQueue.session, current.identifier == identifier else { return }
                    self.postEvent(current.timeoutEvent)
                }
            }
            return true
        }
    }

    func finishRewrite() {
        rewriteInputQueue.synchronized {
            guard let session = rewriteInputQueue.session, session.finishing == false else { return }
            session.finishing = true
            // This fence follows all replacement events at the same injection point. The event-tap
            // thread drains held input downstream only after observing it, never from the main actor.
            postEvent(session.completionEvent)
        }
    }

    func canContinueRewrite() -> Bool {
        rewriteInputQueue.synchronized {
            guard let session = rewriteInputQueue.session else { return false }
            return session.aborted == false && DispatchTime.now().uptimeNanoseconds < session.deadline
                && session.isContextCurrent()
        }
    }

    func latestEventSequence() -> UInt64 {
        eventSequenceClock.current()
    }

    @discardableResult
    func armCorrectionUndo(expiresAt: Date, expectedSequence: UInt64,
                           contextIsCurrent: @escaping @Sendable () -> Bool) -> Bool {
        rewriteInputQueue.synchronized {
            guard eventSequenceClock.current() == expectedSequence else { return false }
            undoEscapeGate.arm(expiresAt: expiresAt, contextIsCurrent: contextIsCurrent)
            return true
        }
    }

    func invalidateCorrectionUndo() { undoEscapeGate.invalidate() }

    private func runEventTapLoop() {
        let mask = [CGEventType.keyDown, .keyUp, .flagsChanged, .leftMouseDown, .rightMouseDown, .otherMouseDown, .scrollWheel]
            .reduce(CGEventMask(0)) { $0 | (1 << $1.rawValue) }
        let callback: CGEventTapCallBack = { proxy, type, event, userInfo in
            guard let userInfo else {
                return Unmanaged.passUnretained(event)
            }

            let monitor = Unmanaged<InputMonitor>.fromOpaque(userInfo).takeUnretainedValue()
            return monitor.handle(eventType: type, event: event, proxy: proxy)
        }

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(mask),
            callback: callback,
            userInfo: UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        ) else {
            statusHandler?(.eventTapCreationFailed)
            return
        }

        statusHandler?(.eventTapCreated)
        eventTap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        let runLoop = CFRunLoopGetCurrent()
        self.runLoop = runLoop
        CFRunLoopAddSource(runLoop, source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        CFRunLoopRun()
    }

    func handle(eventType: CGEventType, event: CGEvent, proxy: CGEventTapProxy? = nil) -> Unmanaged<CGEvent>? {
        rewriteInputQueue.synchronized {
            handleSerialized(eventType: eventType, event: event, proxy: proxy)
        }
    }

    private func handleSerialized(eventType: CGEventType, event: CGEvent, proxy: CGEventTapProxy?) -> Unmanaged<CGEvent>? {
        let marker = event.getIntegerValueField(.eventSourceUserData)
        if let signal = RewriteInputQueue.signal(from: event) {
            if let session = rewriteInputQueue.session, session.identifier == signal.identifier {
                if signal.signal == .completion, session.finishing {
                    drainHeldInput(session, proxy: proxy)
                    rewriteInputQueue.session = nil
                    if stopAfterRewrite { stopEventTap() }
                } else if signal.signal == .timeout {
                    session.aborted = true
                    drainHeldInput(session, proxy: proxy)
                }
            }
            return nil
        }

        if marker != AppConstants.syntheticEventMarker, consumingEscape,
           [.keyDown, .keyUp].contains(eventType),
           event.getIntegerValueField(.keyboardEventKeycode) == Int64(kVK_Escape) {
            if eventType == .keyUp { consumingEscape = false }
            return nil
        }

        if let session = rewriteInputQueue.session {
            if !session.aborted {
                let contextIsCurrent = session.isContextCurrent()
                let expired = DispatchTime.now().uptimeNanoseconds >= session.deadline
                let interrupted = [.leftMouseDown, .rightMouseDown, .otherMouseDown, .scrollWheel,
                                   .tapDisabledByTimeout, .tapDisabledByUserInput].contains(eventType)
                    || (eventType == .keyDown && !event.flags.intersection([.maskCommand, .maskControl]).isEmpty)
                if !contextIsCurrent || expired || interrupted {
                    session.aborted = true
                    drainHeldInput(session, proxy: proxy)
                    if contextIsCurrent && marker != AppConstants.syntheticEventMarker { translateForReplay(event) }
                }
            }
            if marker == AppConstants.syntheticEventMarker {
                // Always release a synthetic key that may already have reached the application.
                return session.aborted && eventType != .keyUp ? nil : Unmanaged.passUnretained(event)
            }
            if !session.aborted, [.keyDown, .keyUp, .flagsChanged].contains(eventType) {
                if session.events.count < rewriteInputQueue.capacity, let copy = event.copy() {
                    let sequence = eventType == .keyDown ? eventSequenceClock.advance() : nil
                    undoEscapeGate.invalidate()
                    session.events.append(.init(event: copy, sequence: sequence))
                    return nil
                }
                // Fail open on overflow, after releasing the earlier keys. Pending replacement
                // events are discarded until the completion fence closes the aborted session.
                session.aborted = true
                drainHeldInput(session, proxy: proxy)
                translateForReplay(event)
            }
        }
        if marker == AppConstants.syntheticEventMarker { return Unmanaged.passUnretained(event) }
        return handleOrdinaryEvent(eventType: eventType, event: event)
    }

    private func drainHeldInput(_ session: RewriteInputQueue.Session, proxy: CGEventTapProxy?) {
        let events = session.events
        session.events.removeAll(keepingCapacity: false)
        guard !events.isEmpty else { return }
        guard session.isContextCurrent() else {
            // Never replay typing into a different field or a newly secured input context.
            deliver(.reset)
            return
        }
        for held in events {
            let event = held.event
            translateForReplay(event)
            if let sequence = held.sequence {
                deliver(normalizedKeyboardEvent(event), sequence: sequence)
            }
            // tapPostEvent enters downstream of our own tap, preserving order without recapture.
            forwardHeldEvent(event, proxy)
        }
    }

    private func translateForReplay(_ event: CGEvent) {
        guard [.keyDown, .keyUp].contains(event.type),
              event.flags.intersection([.maskCommand, .maskControl]).isEmpty,
              let characters = characterResolver.characters(
                keyCode: UInt16(event.getIntegerValueField(.keyboardEventKeycode)), flags: event.flags
              )
        else { return }
        let utf16 = Array(characters.utf16)
        utf16.withUnsafeBufferPointer {
            event.keyboardSetUnicodeString(stringLength: $0.count, unicodeString: $0.baseAddress)
        }
    }

    private func handleOrdinaryEvent(eventType: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if eventType == .tapDisabledByTimeout || eventType == .tapDisabledByUserInput {
            undoEscapeGate.invalidate()
            consumingEscape = false
            deliver(.reset)
            if let eventTap { CGEvent.tapEnable(tap: eventTap, enable: true) }
            return Unmanaged.passUnretained(event)
        }

        if eventType == .keyUp {
            if consumingEscape,
               event.getIntegerValueField(.keyboardEventKeycode) == Int64(kVK_Escape) {
                consumingEscape = false
                return nil
            }
            return Unmanaged.passUnretained(event)
        }
        guard eventType == .keyDown else {
            if [.leftMouseDown, .rightMouseDown, .otherMouseDown, .scrollWheel].contains(eventType) {
                undoEscapeGate.invalidate()
                deliver(.reset)
            }
            return Unmanaged.passUnretained(event)
        }

        let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
        let flags = event.flags
        if consumingEscape, keyCode == UInt16(kVK_Escape) { return nil }
        let isBareEscape = keyCode == UInt16(kVK_Escape)
            && flags.intersection([.maskCommand, .maskControl, .maskAlternate, .maskShift]).isEmpty
        if isBareEscape, undoEscapeGate.claim() {
            consumingEscape = true
            deliver(.undoCorrection)
            return nil
        }
        undoEscapeGate.invalidate()

        reportFirstKeyDownIfNeeded()

        deliver(normalizedKeyboardEvent(event))
        return Unmanaged.passUnretained(event)
    }

    private func normalizedKeyboardEvent(_ event: CGEvent) -> NormalizedInputEvent {
        var length = 0
        event.keyboardGetUnicodeString(maxStringLength: 8, actualStringLength: &length, unicodeString: nil)
        var buffer = Array(repeating: UniChar(0), count: max(length, 1))
        event.keyboardGetUnicodeString(maxStringLength: buffer.count, actualStringLength: &length, unicodeString: &buffer)
        return normalizedEvent(
            keyCode: UInt16(event.getIntegerValueField(.keyboardEventKeycode)),
            fallbackCharacters: String(utf16CodeUnits: buffer, count: length), flags: event.flags
        ) ?? .reset
    }

    private func deliver(_ event: NormalizedInputEvent, sequence: UInt64? = nil) {
        let monitoredEvent = MonitoredInputEvent(sequence: sequence ?? eventSequenceClock.advance(), event: event)
        processingQueue.async { [eventHandler] in eventHandler?(monitoredEvent) }
    }

    private func reportFirstKeyDownIfNeeded() {
        firstKeyEventLock.lock()
        let shouldReport = didReportFirstKeyEvent == false
        didReportFirstKeyEvent = true
        firstKeyEventLock.unlock()

        if shouldReport {
            statusHandler?(.firstKeyDownObserved)
        }
    }

    func normalizedEvent(
        keyCode: UInt16,
        fallbackCharacters: String?,
        flags: CGEventFlags
    ) -> NormalizedInputEvent? {
        let characters = characterResolver.characters(keyCode: keyCode, flags: flags)
            ?? fallbackCharacters
        return normalizer.normalize(keyCode: keyCode, characters: characters, flags: flags)
    }
}
