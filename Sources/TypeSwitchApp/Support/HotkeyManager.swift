import Carbon
import Foundation

@MainActor
final class HotkeyManager {
    private enum HotkeyID: UInt32 {
        case toggleAutoFix = 1
    }

    private let onToggleAutoFix: () -> Void
    private var shortcut: HotkeyShortcut
    private var hotKeyRefs: [EventHotKeyRef?] = []
    private var handlerRef: EventHandlerRef?

    init(
        shortcut: HotkeyShortcut,
        onToggleAutoFix: @escaping () -> Void
    ) {
        self.shortcut = shortcut
        self.onToggleAutoFix = onToggleAutoFix
    }

    func start() {
        guard handlerRef == nil else {
            return
        }

        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, userData in
                guard let userData else {
                    return noErr
                }

                let manager = Unmanaged<HotkeyManager>.fromOpaque(userData).takeUnretainedValue()
                var hotKeyID = EventHotKeyID()
                GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hotKeyID
                )
                manager.handle(hotKeyID.id)
                return noErr
            },
            1,
            &eventType,
            UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque()),
            &handlerRef
        )

        registerHotkeys()
    }

    func updateShortcut(_ shortcut: HotkeyShortcut) {
        self.shortcut = shortcut
        unregisterHotkeys()
        if handlerRef != nil {
            registerHotkeys()
        }
    }

    func stop() {
        unregisterHotkeys()
        if let handlerRef {
            RemoveEventHandler(handlerRef)
        }
        handlerRef = nil
    }

    private func registerHotkeys() {
        hotKeyRefs = [
            register(
                id: .toggleAutoFix,
                keyCode: shortcut.key.carbonKeyCode,
                modifiers: shortcut.modifiers.carbonFlags
            )
        ]
    }

    private func unregisterHotkeys() {
        hotKeyRefs.forEach { hotKeyRef in
            if let hotKeyRef {
                UnregisterEventHotKey(hotKeyRef)
            }
        }
        hotKeyRefs.removeAll()
    }

    private func register(id: HotkeyID, keyCode: UInt32, modifiers: UInt32) -> EventHotKeyRef? {
        let hotKeyID = EventHotKeyID(signature: OSType(0x54595357), id: id.rawValue)
        var hotKeyRef: EventHotKeyRef?
        RegisterEventHotKey(keyCode, modifiers, hotKeyID, GetApplicationEventTarget(), 0, &hotKeyRef)
        return hotKeyRef
    }

    private func handle(_ rawID: UInt32) {
        guard let hotkeyID = HotkeyID(rawValue: rawID) else {
            return
        }

        switch hotkeyID {
        case .toggleAutoFix:
            onToggleAutoFix()
        }
    }
}
