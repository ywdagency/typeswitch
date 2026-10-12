import AppKit
import Carbon
import SwiftUI

struct ShortcutRecorder: NSViewRepresentable {
    @Binding var shortcut: HotkeyShortcut

    func makeNSView(context: Context) -> ShortcutRecorderButton {
        let button = ShortcutRecorderButton()
        button.shortcut = shortcut
        button.onChange = { shortcut = $0 }
        return button
    }

    func updateNSView(_ button: ShortcutRecorderButton, context: Context) {
        button.shortcut = shortcut
        button.onChange = { shortcut = $0 }
    }
}

final class ShortcutRecorderButton: NSButton {
    var shortcut: HotkeyShortcut = .defaultToggleAutoFix {
        didSet {
            guard isRecording == false else {
                return
            }
            title = shortcut.displayText
        }
    }

    var onChange: ((HotkeyShortcut) -> Void)?
    private var isRecording = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        bezelStyle = .rounded
        setButtonType(.momentaryPushIn)
        target = self
        action = #selector(beginRecording)
        focusRingType = .none
        title = shortcut.displayText
    }

    required init?(coder: NSCoder) {
        nil
    }

    override var acceptsFirstResponder: Bool {
        true
    }

    override func keyDown(with event: NSEvent) {
        guard isRecording else {
            super.keyDown(with: event)
            return
        }

        if event.keyCode == UInt16(kVK_Escape) {
            finishRecording()
            return
        }

        guard let captured = HotkeyShortcut.captured(
            keyCode: event.keyCode,
            modifierFlags: event.modifierFlags
        ) else {
            NSSound.beep()
            return
        }

        shortcut = captured
        onChange?(captured)
        finishRecording()
    }

    @objc
    private func beginRecording() {
        isRecording = true
        title = "Press shortcut…"
        window?.makeFirstResponder(self)
    }

    private func finishRecording() {
        isRecording = false
        title = shortcut.displayText
        window?.makeFirstResponder(nil)
    }
}
