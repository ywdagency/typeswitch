import AppKit
import Foundation

protocol SoundFeedbackPlaying {
    func playCorrectionSuccess()
    func playAutoFixToggleClick()
}

final class SystemSoundFeedbackPlayer: SoundFeedbackPlaying {
    private let clickSound = NSSound(named: NSSound.Name("Pop"))
        ?? NSSound(named: NSSound.Name("Tink"))

    func playCorrectionSuccess() {
        playFromStart(clickSound)
    }

    func playAutoFixToggleClick() {
        playFromStart(clickSound)
    }

    private func playFromStart(_ sound: NSSound?) {
        guard let sound else {
            NSSound.beep()
            return
        }

        sound.stop()
        sound.currentTime = 0
        sound.play()
    }
}
