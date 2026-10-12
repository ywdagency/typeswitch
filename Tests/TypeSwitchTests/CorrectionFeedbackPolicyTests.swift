import Foundation
import Testing
@testable import TypeSwitchApp

@Test
func successSoundRequiresActualTextRewrite() {
    #expect(CorrectionFeedbackPolicy.shouldPlaySuccessSound(
        didRewriteText: true,
        soundFeedbackEnabled: true
    ))

    #expect(CorrectionFeedbackPolicy.shouldPlaySuccessSound(
        didRewriteText: false,
        soundFeedbackEnabled: true
    ) == false)

    #expect(CorrectionFeedbackPolicy.shouldPlaySuccessSound(
        didRewriteText: true,
        soundFeedbackEnabled: false
    ) == false)
}

@MainActor
@Test
func autoFixTogglePlaysOneClickPerStateChange() {
    let fixture = IsolatedUserDefaults()
    let soundPlayer = FakeSoundFeedbackPlayer()
    let appModel = AppModel()
    let coordinator = LayoutCoordinator(
        appModel: appModel,
        appSettingsStore: AppSettingsStore(defaults: fixture.defaults),
        soundFeedbackPlayer: soundPlayer
    )

    coordinator.toggleAutoFix()
    #expect(appModel.autoFixEnabled == false)
    #expect(soundPlayer.toggleClickCount == 1)

    coordinator.setAutoFixEnabled(false)
    #expect(soundPlayer.toggleClickCount == 1)

    coordinator.toggleAutoFix()
    #expect(appModel.autoFixEnabled)
    #expect(soundPlayer.toggleClickCount == 2)
}

private final class FakeSoundFeedbackPlayer: SoundFeedbackPlaying {
    var toggleClickCount = 0

    func playCorrectionSuccess() {}

    func playAutoFixToggleClick() {
        toggleClickCount += 1
    }
}
