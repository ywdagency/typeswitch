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

final class SyntheticInputSuppressionGate: @unchecked Sendable {
    private let lock = NSLock()
    private var suppressedUntil: UInt64 = 0

    func suppress(forNanoseconds duration: UInt64, now: UInt64 = DispatchTime.now().uptimeNanoseconds) {
        lock.lock()
        suppressedUntil = max(suppressedUntil, now &+ duration)
        lock.unlock()
    }

    func shouldSuppress(
        eventMarker: Int64,
        syntheticMarker: Int64,
        now: UInt64 = DispatchTime.now().uptimeNanoseconds
    ) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return eventMarker == syntheticMarker || now < suppressedUntil
    }
}

final class InputMonitor: @unchecked Sendable {
    typealias EventHandler = @Sendable (MonitoredInputEvent) -> Void

    private let normalizer: InputEventNormalizer
    private let characterResolver: KeyboardCharacterResolving
    private let syntheticInputSuppressionGate: SyntheticInputSuppressionGate
    private let eventSequenceClock: InputEventSequenceClock
    private let processingQueue = DispatchQueue(label: AppConstants.inputMonitorQueueLabel)
    private let firstKeyEventLock = NSLock()
    private var didReportFirstKeyEvent = false
    private var eventHandler: EventHandler?
    private var statusHandler: (@Sendable (InputMonitorStatus) -> Void)?
    private var eventTap: CFMachPort?
    private var runLoop: CFRunLoop?
    private var tapThread: Thread?

    init(
        normalizer: InputEventNormalizer = InputEventNormalizer(),
        characterResolver: KeyboardCharacterResolving = SystemKeyboardCharacterResolver(),
        syntheticInputSuppressionGate: SyntheticInputSuppressionGate = SyntheticInputSuppressionGate(),
        eventSequenceClock: InputEventSequenceClock = InputEventSequenceClock()
    ) {
        self.normalizer = normalizer
        self.characterResolver = characterResolver
        self.syntheticInputSuppressionGate = syntheticInputSuppressionGate
        self.eventSequenceClock = eventSequenceClock
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
        eventHandler = nil
        if let eventTap {
            CFMachPortInvalidate(eventTap)
        }
        if let runLoop {
            CFRunLoopStop(runLoop)
        }
        eventTap = nil
        tapThread = nil
    }

    func suppressSyntheticEvents() {
        syntheticInputSuppressionGate.suppress(
            forNanoseconds: AppConstants.syntheticEventSuppressionNanoseconds
        )
    }

    func latestEventSequence() -> UInt64 {
        eventSequenceClock.current()
    }

    private func runEventTapLoop() {
        let mask = (1 << CGEventType.keyDown.rawValue)
        let callback: CGEventTapCallBack = { _, type, event, userInfo in
            guard let userInfo else {
                return Unmanaged.passUnretained(event)
            }

            let monitor = Unmanaged<InputMonitor>.fromOpaque(userInfo).takeUnretainedValue()
            return monitor.handle(eventType: type, event: event)
        }

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
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

    private func handle(eventType: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if eventType == .tapDisabledByTimeout, let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: true)
            return Unmanaged.passUnretained(event)
        }

        guard eventType == .keyDown else {
            return Unmanaged.passUnretained(event)
        }

        guard syntheticInputSuppressionGate.shouldSuppress(
            eventMarker: event.getIntegerValueField(.eventSourceUserData),
            syntheticMarker: AppConstants.syntheticEventMarker
        ) == false else {
            return Unmanaged.passUnretained(event)
        }

        reportFirstKeyDownIfNeeded()

        let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
        let flags = event.flags
        var length = 0
        event.keyboardGetUnicodeString(maxStringLength: 8, actualStringLength: &length, unicodeString: nil)
        var buffer = Array(repeating: UniChar(0), count: max(length, 1))
        event.keyboardGetUnicodeString(maxStringLength: buffer.count, actualStringLength: &length, unicodeString: &buffer)
        let fallbackCharacters = String(utf16CodeUnits: buffer, count: length)

        if let normalized = normalizedEvent(
            keyCode: keyCode,
            fallbackCharacters: fallbackCharacters,
            flags: flags
        ) {
            processingQueue.async { [eventHandler, eventSequenceClock] in
                eventHandler?(
                    MonitoredInputEvent(
                        sequence: eventSequenceClock.advance(),
                        event: normalized
                    )
                )
            }
        }

        return Unmanaged.passUnretained(event)
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
