import Foundation
import Observation

@MainActor
@Observable
final class AppModel {
    enum OperatingMode: String {
        case starting
        case permissionsRequired
        case ready
        case monitoring
        case blocked
    }

    var permissionState: PermissionState = .unknown
    var operatingMode: OperatingMode = .starting
    var statusMessage = "Starting TypeSwitch..."
    var autoFixEnabled = true
    var soundFeedbackEnabled = true
    var diagnosticsEnabled = false
    var toggleAutoFixHotkey = HotkeyShortcut.defaultToggleAutoFix
    var inputSourceOptions: [InputSourceOption] = []
    var availableLayouts: [KeyboardLayout] = []
    var participatingLayouts: Set<KeyboardLayout> = []
    var preferredInputSourceIDs: [KeyboardLayout: String] = [:]
    var dictionaryCoverageDescription = "Loading local dictionaries…"
    var currentBundleID: String?
    var currentContextDescription = "No focused text input detected."
    var focusedElementDiagnosticSummary = "No focused AX diagnostic captured yet."
    var supportedContextDescription = "Auto-fix runs in ordinary editable fields unless the app is ignored."
    var ignoredApps: [AppPolicy] = []
    var pendingLearningCandidate: PendingLearningCandidate?
    var learnedCorrections: [CorrectionDictionaryEntry] = []
    var correctionExceptions: [CorrectionException] = []
    var diagnostics: [DiagnosticEvent] = []

    var permissionSummary: String {
        permissionState.summary
    }

    func updateDiagnostics(_ events: [DiagnosticEvent]) {
        diagnostics = events
    }
}
