import AppKit
import Foundation

@MainActor
final class LayoutCoordinator {
    private let appModel: AppModel
    private let permissionsController: PermissionsController
    private let inputSourceController: InputSourceController
    private let focusedElementResolver: FocusedElementResolving
    private let inputMonitor: InputMonitor
    private let inferenceEngine: LayoutInferenceEngine
    private let learnedCorrectionStore: LearnedCorrectionStore
    private let learningCandidatePresentationPolicy: LearningCandidatePresentationPolicy
    private let diagnosticDictionaryStore: CorrectionDictionaryStore
    private let rewriteEngine: AXRewriteEngine
    private let syntheticFallbackRewriteEngine: SyntheticTextFallbackRewriting
    private let diagnosticsLogger: DiagnosticsLogger
    private let appSettingsStore: AppSettingsStore
    private let appPolicyStore: AppPolicyStore
    private let soundFeedbackPlayer: SoundFeedbackPlaying
    private var hotkeyManager: HotkeyManager?
    private var bufferManager = BufferManager()
    private var languageSwitchEvidence = LanguageSwitchEvidenceTracker()
    private var autoCorrectionUndoTracker = AutoCorrectionUndoTracker()
    private var inputSourceObservationTask: Task<Void, Never>?
    private var permissionObservationTask: Task<Void, Never>?
    private var hasActivated = false

    init(
        appModel: AppModel,
        permissionsController: PermissionsController = PermissionsController(),
        inputSourceController: InputSourceController = InputSourceController(),
        focusedElementResolver: FocusedElementResolving = AXFocusedElementResolver(),
        inputMonitor: InputMonitor = InputMonitor(),
        inferenceEngine: LayoutInferenceEngine? = nil,
        learnedCorrectionStore: LearnedCorrectionStore = LearnedCorrectionStore(),
        learningCandidateWordValidator: LearningCandidateWordValidating = SystemLearningCandidateWordValidator(),
        diagnosticDictionaryStore: CorrectionDictionaryStore = CorrectionDictionaryStore(),
        rewriteEngine: AXRewriteEngine = AXRewriteEngine(),
        syntheticFallbackRewriteEngine: SyntheticTextFallbackRewriting = SyntheticTextFallbackRewriteEngine(),
        diagnosticsLogger: DiagnosticsLogger = DiagnosticsLogger(),
        appSettingsStore: AppSettingsStore = AppSettingsStore(),
        appPolicyStore: AppPolicyStore = AppPolicyStore(),
        soundFeedbackPlayer: SoundFeedbackPlaying = SystemSoundFeedbackPlayer()
    ) {
        self.appModel = appModel
        self.permissionsController = permissionsController
        self.inputSourceController = inputSourceController
        self.focusedElementResolver = focusedElementResolver
        self.inputMonitor = inputMonitor
        self.learnedCorrectionStore = learnedCorrectionStore
        self.learningCandidatePresentationPolicy = LearningCandidatePresentationPolicy(
            validator: learningCandidateWordValidator
        )
        self.inferenceEngine = inferenceEngine ?? LayoutInferenceEngine(
            dictionaryStore: CorrectionDictionaryStore(learnedStore: learnedCorrectionStore)
        )
        self.diagnosticDictionaryStore = diagnosticDictionaryStore
        self.rewriteEngine = rewriteEngine
        self.syntheticFallbackRewriteEngine = syntheticFallbackRewriteEngine
        self.diagnosticsLogger = diagnosticsLogger
        self.appSettingsStore = appSettingsStore
        self.appPolicyStore = appPolicyStore
        self.soundFeedbackPlayer = soundFeedbackPlayer
    }

    func activate() async {
        guard hasActivated == false else {
            return
        }
        hasActivated = true
        diagnosticsLogger.logTrace("coordinator activationStarted")

        loadPersistedSettings()
        refreshInputSourceOptions()
        startObservingInputSourceChanges()
        startObservingPermissionChanges()

        installHotkeys()
        refreshPermissions()
        diagnosticsLogger.logTrace(
            "permissions inputMonitoring=\(appModel.permissionState.inputMonitoring.rawValue) accessibility=\(appModel.permissionState.accessibility.rawValue)"
        )
    }

    func refreshPermissions() {
        applyPermissionState(permissionsController.refreshState())
    }

    func requestPermission(_ permission: RequiredPermission) {
        applyPermissionState(permissionsController.request(permission))
        PermissionSettingsOpener.openSettings(for: permission)
    }

    private func applyPermissionState(_ state: PermissionState) {
        let wasReady = appModel.permissionState.isReadyForManualCorrection
        if state != appModel.permissionState {
            diagnosticsLogger.logTrace("permissions inputMonitoring=\(state.inputMonitoring.rawValue) accessibility=\(state.accessibility.rawValue)")
        }
        appModel.permissionState = state
        if state.isReadyForManualCorrection {
            if hasActivated && appModel.operatingMode != .monitoring {
                startMonitoring()
            } else if hasActivated == false {
                appModel.operatingMode = .ready
            }
            appModel.statusMessage = "TypeSwitch is ready. Auto-fix is available in supported fields."
        } else {
            if wasReady && hasActivated {
                inputMonitor.stop()
                _ = bufferManager.consume(.reset)
                languageSwitchEvidence.reset()
                autoCorrectionUndoTracker.invalidate()
                appModel.pendingLearningCandidate = nil
            }
            appModel.operatingMode = .permissionsRequired
            appModel.statusMessage = state.missingSummary
        }
    }

    private func startObservingPermissionChanges() {
        guard permissionObservationTask == nil else { return }
        permissionObservationTask = Task { @MainActor [weak self] in
            for await _ in NotificationCenter.default.notifications(
                named: NSApplication.didBecomeActiveNotification
            ) {
                guard let self else { return }
                self.refreshPermissions()
            }
        }
    }

    func refreshFocusDiagnostic() {
        guard let snapshot = resolveContext(includeTreeDiagnostic: true) else {
            appModel.focusedElementDiagnosticSummary = "No focused editable text input."
            appModel.currentContextDescription = "No focused editable text input."
            appModel.statusMessage = BlockedReason.missingFocusedElement.userFacingDescription
            return
        }

        appModel.currentBundleID = snapshot.context.frontmostBundleID
        appModel.currentContextDescription = snapshot.context.summary
        appModel.focusedElementDiagnosticSummary = snapshot.diagnostic.summary
        diagnosticsLogger.logFocusDiagnostic(summary: snapshot.diagnostic.summary)
        appModel.statusMessage = "Focused AX diagnostic refreshed."
    }

    func setAutoFixEnabled(_ enabled: Bool) {
        guard appModel.autoFixEnabled != enabled else {
            return
        }

        appModel.autoFixEnabled = enabled
        autoCorrectionUndoTracker.invalidate()
        appSettingsStore.setAutoFixEnabled(enabled)
        soundFeedbackPlayer.playAutoFixToggleClick()
        appModel.statusMessage = enabled
            ? "Dictionary auto-fix is enabled for writable non-sensitive fields."
            : "Auto-fix is disabled. Manual correction remains available."
    }

    func toggleAutoFix() {
        setAutoFixEnabled(appModel.autoFixEnabled == false)
    }

    func setToggleAutoFixHotkey(_ shortcut: HotkeyShortcut) {
        appModel.toggleAutoFixHotkey = shortcut
        appSettingsStore.setToggleAutoFixHotkey(shortcut)
        hotkeyManager?.updateShortcut(shortcut)
    }

    func refreshLearningCandidate() {
        guard let candidate = appModel.pendingLearningCandidate,
              candidate.isExpired
        else {
            return
        }
        appModel.pendingLearningCandidate = nil
    }

    @discardableResult
    func learnPendingCorrection() -> CorrectionDictionaryEntry? {
        refreshLearningCandidate()
        guard let candidate = appModel.pendingLearningCandidate else {
            return nil
        }

        learnedCorrectionStore.add(candidate.entry)
        appModel.pendingLearningCandidate = nil
        refreshLearnedCorrections()
        appModel.statusMessage = "Learned a local correction."
        return candidate.entry
    }

    func removeLearnedCorrection(id: String) {
        learnedCorrectionStore.remove(id: id)
        refreshLearnedCorrections()
    }

    func setLayout(_ layout: KeyboardLayout, participates: Bool) {
        var layouts = appModel.participatingLayouts
        if participates {
            layouts.insert(layout)
        } else {
            guard layouts.count > 2 else {
                appModel.statusMessage = "At least two languages must participate."
                return
            }
            layouts.remove(layout)
        }
        guard layouts.count >= 2 else {
            return
        }
        appModel.participatingLayouts = layouts
        appSettingsStore.setParticipatingLayouts(layouts)
        languageSwitchEvidence.reset()
    }

    func refreshIgnoredApps() {
        appModel.ignoredApps = appPolicyStore.allPolicies()
    }

    @discardableResult
    func addIgnoredApp(at url: URL) -> Bool {
        let url = url.resolvingSymlinksInPath()
        guard url.pathExtension.lowercased() == "app",
              let bundle = Bundle(url: url),
              let bundleID = bundle.bundleIdentifier,
              bundleID != AppConstants.bundleIdentifier
        else {
            appModel.statusMessage = "Choose a macOS application."
            return false
        }

        let displayName = (bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
            ?? (bundle.object(forInfoDictionaryKey: "CFBundleName") as? String)
            ?? url.deletingPathExtension().lastPathComponent
        appPolicyStore.upsert(bundleID: bundleID, displayName: displayName, mode: .disabled)
        refreshIgnoredApps()
        appModel.statusMessage = "TypeSwitch will not change text in \(displayName)."
        return true
    }

    func removeIgnoredApp(bundleID: String) {
        appPolicyStore.forget(bundleID: bundleID)
        refreshIgnoredApps()
        appModel.statusMessage = "App removed from the ignore list."
    }

    private func installHotkeys() {
        guard hotkeyManager == nil else {
            return
        }

        let manager = HotkeyManager(
            shortcut: appModel.toggleAutoFixHotkey,
            onToggleAutoFix: { [weak self] in
                Task { @MainActor in
                    self?.toggleAutoFix()
                }
            }
        )
        manager.start()
        hotkeyManager = manager
    }

    private func loadPersistedSettings() {
        appModel.autoFixEnabled = appSettingsStore.autoFixEnabled()
        appModel.soundFeedbackEnabled = true
        appSettingsStore.setSoundFeedbackEnabled(true)
        appModel.diagnosticsEnabled = false
        appSettingsStore.setDiagnosticsEnabled(false)
        appModel.toggleAutoFixHotkey = appSettingsStore.toggleAutoFixHotkey()
        appModel.dictionaryCoverageDescription = "\(diagnosticDictionaryStore.count(for: .english).formatted()) English · \(diagnosticDictionaryStore.count(for: .russian).formatted()) Russian · \(diagnosticDictionaryStore.count(for: .ukrainian).formatted()) Ukrainian words"
        refreshIgnoredApps()
        refreshLearnedCorrections()
    }

    private func refreshInputSourceOptions() {
        let options = inputSourceController.availableSourceOptions()
        appModel.inputSourceOptions = options
        let availableLayouts = KeyboardLayout.allCases.filter { layout in
            options.contains(where: { $0.keyboardLayout == layout })
        }
        appModel.availableLayouts = availableLayouts

        let availableSet = Set(availableLayouts)
        let stored = appSettingsStore.participatingLayouts()
        let participating = (stored ?? availableSet).intersection(availableSet)
        appModel.participatingLayouts = participating.count >= 2 ? participating : availableSet
        appSettingsStore.setParticipatingLayouts(appModel.participatingLayouts)

        for layout in availableLayouts {
            let available = options.filter { $0.keyboardLayout == layout }
            let storedID = appSettingsStore.preferredInputSourceID(for: layout)
            let sourceID = available.first(where: { $0.sourceID == storedID })?.sourceID
                ?? available.first?.sourceID
            if let sourceID {
                appModel.preferredInputSourceIDs[layout] = sourceID
            }
        }
    }

    private func startObservingInputSourceChanges() {
        guard inputSourceObservationTask == nil else { return }
        inputSourceObservationTask = Task { @MainActor [weak self] in
            for await _ in NotificationCenter.default.notifications(
                named: NSTextInputContext.keyboardSelectionDidChangeNotification
            ) {
                guard let self else { return }
                self.handleInputSourceChange()
            }
        }
    }

    private func handleInputSourceChange() {
        _ = bufferManager.consume(.reset)
        languageSwitchEvidence.reset()
        inputMonitor.refreshKeyboardLayout()
        refreshInputSourceOptions()
        guard let layout = inputSourceController.currentLayout(),
              let sourceID = inputSourceController.currentSourceIdentifier()
        else { return }
        appModel.preferredInputSourceIDs[layout] = sourceID
        appSettingsStore.setPreferredInputSourceID(sourceID, for: layout)
    }

    private func startMonitoring() {
        diagnosticsLogger.logTrace("inputMonitor startRequested")
        inputMonitor.start(
            eventHandler: { [weak self] monitoredEvent in
                Task { @MainActor in
                    self?.consumeMonitoredEvent(monitoredEvent)
                }
            },
            statusHandler: { [weak self] status in
                Task { @MainActor in
                    self?.diagnosticsLogger.logTrace("inputMonitor status=\(status.rawValue)")
                }
            }
        )
        appModel.operatingMode = .monitoring
    }

    private func consumeMonitoredEvent(_ monitoredEvent: MonitoredInputEvent) {
        let event = monitoredEvent.event
        switch event {
        case .navigation, .paste, .reset:
            appModel.pendingLearningCandidate = nil
        case .text, .delimiter, .backspace:
            refreshLearningCandidate()
        }

        let focusedSnapshot = resolveContext()
        if let snapshot = focusedSnapshot {
            synchronizeLearningCandidate(with: snapshot.context)
            appModel.currentBundleID = snapshot.context.frontmostBundleID
            appModel.currentContextDescription = snapshot.context.summary
            appModel.focusedElementDiagnosticSummary = snapshot.diagnostic.summary
            guard appPolicyStore.mode(for: snapshot.context.frontmostBundleID) != .disabled else {
                autoCorrectionUndoTracker.invalidate()
                _ = bufferManager.consume(.reset)
                return
            }
        } else {
            appModel.currentContextDescription = "No focused editable text input."
        }

        if case .backspace = event,
           let bundleID = focusedSnapshot?.context.frontmostBundleID,
           let candidate = autoCorrectionUndoTracker.takeForImmediateBackspace(bundleID: bundleID) {
            _ = bufferManager.consume(.reset)
            scheduleAutoCorrectionUndo(candidate)
            return
        }
        autoCorrectionUndoTracker.invalidate()

        let outcome = bufferManager.consume(event)

        guard case let .delimiter(delimiter) = event, let completedToken = outcome.completedToken else {
            return
        }

        guard let observedLayout = inputSourceController.currentLayout() else {
            diagnosticsLogger.logTrace("autoFixSkipped reason=unsupportedLayout")
            return
        }

        guard ObservedTokenLayoutPolicy.isConsistent(completedToken, with: observedLayout) else {
            diagnosticsLogger.logTrace("autoFixSkipped reason=layoutSnapshotMismatch")
            inputMonitor.refreshKeyboardLayout()
            return
        }

        let frontmost = NSWorkspace.shared.frontmostApplication
        diagnosticsLogger.logTrace(
            "wordBoundary frontmost=\(frontmost?.bundleIdentifier ?? "unknown") token=\(redactedTokenSummary(completedToken, currentLayout: observedLayout))"
        )
        scheduleAutoFix(
            for: completedToken,
            trailingDelimiter: String(delimiter),
            inputSequence: monitoredEvent.sequence,
            observedLayout: observedLayout,
            snapshot: focusedSnapshot
        )
    }

    private func scheduleAutoFix(
        for token: String,
        trailingDelimiter: String,
        inputSequence: UInt64,
        observedLayout: KeyboardLayout,
        snapshot: AXFocusedElementSnapshot?
    ) {
        guard let snapshot else {
            let frontmost = NSWorkspace.shared.frontmostApplication
            diagnosticsLogger.logTrace(
                "autoFixSkipped reason=missingFocusedElement frontmost=\(frontmost?.bundleIdentifier ?? "unknown")"
            )
            return
        }

        let request = CorrectionRequest(
            source: .autoWordBoundary,
            observedToken: token,
            trailingDelimiter: trailingDelimiter,
            selectionMode: .lastWord,
            context: snapshot.context
        )

        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: AppConstants.autoFixDelayNanoseconds)
            self?.perform(
                request: request,
                element: snapshot.element,
                correctionInputSequence: inputSequence,
                observedLayout: observedLayout
            )
        }
    }

    private func perform(
        request: CorrectionRequest,
        element: AXElementProtocol,
        correctionInputSequence: UInt64,
        observedLayout: KeyboardLayout
    ) {
        guard AutoFixFreshnessPolicy.isFresh(
            scheduledSequence: correctionInputSequence,
            latestSequence: inputMonitor.latestEventSequence()
        ) else {
            diagnosticsLogger.logTrace(
                "autoFixSkipped reason=staleInputSequence bundle=\(request.context.frontmostBundleID)"
            )
            return
        }

        guard appModel.permissionState.isReadyForManualCorrection else {
            let decision: CorrectionDecision = .blocked(.permissionsMissing)
            record(decision: decision, request: request)
            appModel.statusMessage = BlockedReason.permissionsMissing.userFacingDescription
            return
        }

        guard inputSourceController.currentLayout() == observedLayout else {
            let decision: CorrectionDecision = .blocked(.ambiguousEditingState)
            record(decision: decision, request: request)
            diagnosticsLogger.logTrace(
                "autoFixSkipped reason=inputSourceChanged bundle=\(request.context.frontmostBundleID)"
            )
            return
        }
        let currentLayout = observedLayout

        guard appModel.participatingLayouts.contains(currentLayout) else {
            record(decision: .ignore, request: request)
            return
        }

        let proposedDecision = inferenceEngine.inferCorrection(
            for: request.observedToken ?? "",
            currentLayout: currentLayout,
            requiresDictionaryMatch: request.source == .autoWordBoundary
        )

        if proposedDecision == .ignore {
            captureLearningCandidateIfEligible(
                request: request,
                currentLayout: currentLayout
            )
        }
        let participatingDecision = decisionTargetsParticipatingLayout(proposedDecision)
            ? proposedDecision
            : .ignore

        let evaluatedDecision = SafetyGateEvaluator(
            autoFixPolicy: WordBoundaryAutoFixPolicy(
                appPolicyStore: appPolicyStore
            )
        ).evaluate(
            request: adjustedRequestForAutoFix(request),
            proposedDecision: participatingDecision,
            isAutoFixEnabled: appModel.autoFixEnabled
        )

        switch evaluatedDecision {
        case .ignore:
            record(decision: .ignore, request: request)
        case let .blocked(reason):
            record(decision: .blocked(reason), request: request)
            appModel.statusMessage = reason.userFacingDescription
        case let .switchOnly(targetLayout, reason):
            if (currentLayout == .russian || currentLayout == .ukrainian),
               (targetLayout == .russian || targetLayout == .ukrainian),
               languageSwitchEvidence.confirms(target: targetLayout) == false {
                record(decision: .ignore, request: request)
                return
            }
            let didSwitch = switchToLayout(
                targetLayout,
                preferredSourceID: preferredInputSourceID(for: targetLayout)
            )
            record(decision: evaluatedDecision, request: request)
            appModel.statusMessage = didSwitch ? reason : "Could not confirm the keyboard layout switch."
        case let .rewriteAndMaybeSwitch(replacement, targetLayout, reason, _):
            if AXRewriteRoutingPolicy.requiresBoundedFallback(
                bundleID: request.context.frontmostBundleID,
                controlKind: request.context.controlKind,
                accessibilityRole: element.role
            ) {
                diagnosticsLogger.logTrace(
                    "rewriteRouting path=boundedFallback bundle=\(request.context.frontmostBundleID) role=\(element.role ?? "unknown")"
                )
                if performSyntheticFallbackIfAllowed(
                    error: AXElementError.unsupported,
                    request: request,
                    replacement: replacement,
                    targetLayout: targetLayout,
                    sourceLayout: currentLayout,
                    correctionInputSequence: correctionInputSequence,
                    evaluatedDecision: evaluatedDecision,
                    reason: reason
                ) {
                    return
                }

                let failedDecision: CorrectionDecision = .blocked(.rewriteFailed)
                record(decision: failedDecision, request: request)
                appModel.statusMessage = BlockedReason.rewriteFailed.userFacingDescription
                return
            }

            do {
                diagnosticsLogger.logTrace(
                    "rewriteState \(AXRewriteEngine.redactedLastWordRewriteState(in: element, observedToken: request.observedToken))"
                )
                switch request.selectionMode {
                case .selectedText:
                    try rewriteEngine.replaceSelectedText(in: element, replacement: replacement)
                case .lastWord, .none:
                    try rewriteEngine.replaceLastWordAtCaret(
                        in: element,
                        replacement: replacement,
                        observedToken: request.observedToken,
                        strategy: axRewriteStrategy(
                            for: request.context.controlKind,
                            element: element
                        )
                    )
                }
                let didSwitch = switchToLayout(
                    targetLayout,
                    preferredSourceID: preferredInputSourceID(for: targetLayout)
                )
                recordUndoCandidate(
                    request: request,
                    replacement: replacement,
                    sourceLayout: currentLayout,
                    targetLayout: targetLayout,
                    correctionInputSequence: correctionInputSequence
                )
                record(decision: evaluatedDecision, request: request)
                playCorrectionSoundIfEnabled()
                appModel.statusMessage = didSwitch
                    ? reason
                    : "Text was corrected, but the keyboard layout switch was not confirmed."
            } catch {
                if performSyntheticFallbackIfAllowed(
                    error: error,
                    request: request,
                    replacement: replacement,
                    targetLayout: targetLayout,
                    sourceLayout: currentLayout,
                    correctionInputSequence: correctionInputSequence,
                    evaluatedDecision: evaluatedDecision,
                    reason: reason
                ) {
                    return
                }

                let failedDecision: CorrectionDecision = .blocked(.rewriteFailed)
                let errorSummary: String
                if let axError = error as? AXElementError {
                    errorSummary = axError.userFacingDescription
                } else {
                    errorSummary = String(describing: type(of: error))
                }
                diagnosticsLogger.logTrace("rewriteError \(errorSummary)")
                record(decision: failedDecision, request: request)
                if let axError = error as? AXElementError {
                    appModel.statusMessage = "\(BlockedReason.rewriteFailed.userFacingDescription) \(axError.userFacingDescription)"
                } else {
                    appModel.statusMessage = BlockedReason.rewriteFailed.userFacingDescription
                }
            }
        }
    }

    private func adjustedRequestForAutoFix(_ request: CorrectionRequest) -> CorrectionRequest {
        guard request.source == .autoWordBoundary else {
            return request
        }

        return CorrectionRequest(
            source: request.source,
            observedToken: request.observedToken,
            trailingDelimiter: request.trailingDelimiter,
            selectionMode: request.selectionMode,
            context: request.context
        )
    }

    private func performSyntheticFallbackIfAllowed(
        error: Error,
        request: CorrectionRequest,
        replacement: String,
        targetLayout: KeyboardLayout,
        sourceLayout: KeyboardLayout,
        correctionInputSequence: UInt64,
        evaluatedDecision: CorrectionDecision,
        reason: String
    ) -> Bool {
        guard request.source == .autoWordBoundary,
              request.selectionMode == .lastWord,
              syntheticFallbackAllowed(for: request.context.frontmostBundleID),
              NSWorkspace.shared.frontmostApplication?.bundleIdentifier == request.context.frontmostBundleID,
              SyntheticTextFallbackRewriteEngine.canRecover(after: error),
              let observedToken = request.observedToken,
              let trailingDelimiter = request.trailingDelimiter
        else {
            return false
        }

        guard switchToLayout(
            targetLayout,
            preferredSourceID: preferredInputSourceID(for: targetLayout)
        ) else {
            diagnosticsLogger.logTrace("syntheticFallback result=sourceSwitchFailed bundle=\(request.context.frontmostBundleID)")
            return false
        }

        inputMonitor.suppressSyntheticEvents()
        guard syntheticFallbackRewriteEngine.replaceLastToken(
            observedToken: observedToken,
            replacement: replacement,
            trailingDelimiter: trailingDelimiter,
            targetLayout: targetLayout
        ) else {
            diagnosticsLogger.logTrace("syntheticFallback result=refused bundle=\(request.context.frontmostBundleID)")
            return false
        }

        diagnosticsLogger.logTrace("syntheticFallback result=success bundle=\(request.context.frontmostBundleID)")
        recordUndoCandidate(
            request: request,
            replacement: replacement,
            sourceLayout: sourceLayout,
            targetLayout: targetLayout,
            correctionInputSequence: correctionInputSequence
        )
        record(decision: evaluatedDecision, request: request)
        appModel.statusMessage = reason
        return true
    }

    private func recordUndoCandidate(
        request: CorrectionRequest,
        replacement: String,
        sourceLayout: KeyboardLayout,
        targetLayout: KeyboardLayout,
        correctionInputSequence: UInt64
    ) {
        guard request.source == .autoWordBoundary,
              AutoFixFreshnessPolicy.isFresh(
                  scheduledSequence: correctionInputSequence,
                  latestSequence: inputMonitor.latestEventSequence()
              ),
              let originalToken = request.observedToken,
              originalToken.isEmpty == false,
              originalToken != replacement
        else {
            return
        }

        autoCorrectionUndoTracker.record(
            AutoCorrectionUndoCandidate(
                originalToken: originalToken,
                replacementToken: replacement,
                sourceLayout: sourceLayout,
                targetLayout: targetLayout,
                bundleID: request.context.frontmostBundleID,
                expiresAt: Date().addingTimeInterval(AppConstants.autoCorrectionUndoLifetime)
            )
        )
    }

    private func scheduleAutoCorrectionUndo(_ candidate: AutoCorrectionUndoCandidate) {
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: AppConstants.autoCorrectionUndoDelayNanoseconds)
            self?.performAutoCorrectionUndo(candidate)
        }
    }

    private func performAutoCorrectionUndo(_ candidate: AutoCorrectionUndoCandidate) {
        guard NSWorkspace.shared.frontmostApplication?.bundleIdentifier == candidate.bundleID,
              appPolicyStore.mode(for: candidate.bundleID) != .disabled,
              let snapshot = resolveContext(),
              snapshot.context.frontmostBundleID == candidate.bundleID,
              snapshot.context.isSecureInput == false,
              snapshot.context.isPasswordLike == false,
              snapshot.context.isTerminalLike == false,
              snapshot.context.supportsWritableAXText,
              snapshot.context.supportsSelectionRange
        else {
            diagnosticsLogger.logTrace("correctionUndo result=refused bundle=\(candidate.bundleID)")
            return
        }

        do {
            try rewriteEngine.replaceLastWordAtCaret(
                in: snapshot.element,
                replacement: candidate.originalToken,
                observedToken: candidate.replacementToken,
                strategy: axRewriteStrategy(
                    for: snapshot.context.controlKind,
                    element: snapshot.element
                )
            )
            _ = switchToLayout(
                candidate.sourceLayout,
                preferredSourceID: preferredInputSourceID(for: candidate.sourceLayout)
            )
            completeAutoCorrectionUndo(candidate, path: "ax")
        } catch {
            guard syntheticFallbackAllowed(for: candidate.bundleID),
                  SyntheticTextFallbackRewriteEngine.canRecover(after: error),
                  switchToLayout(
                    candidate.sourceLayout,
                    preferredSourceID: preferredInputSourceID(for: candidate.sourceLayout)
                  )
            else {
                diagnosticsLogger.logTrace("correctionUndo result=failed bundle=\(candidate.bundleID)")
                return
            }
            inputMonitor.suppressSyntheticEvents()
            guard syntheticFallbackRewriteEngine.replaceLastToken(
                    observedToken: candidate.replacementToken,
                    replacement: candidate.originalToken,
                    trailingDelimiter: "",
                    targetLayout: candidate.sourceLayout
                  )
            else {
                diagnosticsLogger.logTrace("correctionUndo result=failed bundle=\(candidate.bundleID)")
                return
            }
            completeAutoCorrectionUndo(candidate, path: "fallback")
        }
    }

    private func completeAutoCorrectionUndo(_ candidate: AutoCorrectionUndoCandidate, path: String) {
        diagnosticsLogger.logTrace("correctionUndo result=success path=\(path) bundle=\(candidate.bundleID)")
        appModel.statusMessage = "Correction undone. The next occurrence can be corrected again."
    }

    private func syntheticFallbackAllowed(for bundleID: String) -> Bool {
        return appPolicyStore.mode(for: bundleID).allowsSyntheticFallback
    }

    @discardableResult
    private func switchToLayout(_ layout: KeyboardLayout, preferredSourceID: String?) -> Bool {
        let didSwitch = inputSourceController.switchToLayout(
            layout,
            preferredSourceID: preferredSourceID
        )
        if didSwitch {
            inputMonitor.refreshKeyboardLayout()
        }
        return didSwitch
    }

    private func axRewriteStrategy(
        for controlKind: AppContext.ControlKind,
        element: AXElementProtocol
    ) -> AXLastWordRewriteStrategy {
        switch controlKind {
        case .browserTextInput, .browserTextArea, .browserContentEditable:
            .selectedTextOnly
        case .nativeTextInput where element.isSelectedTextSettable:
            .selectedTextOnly
        case .nativeTextInput, .terminal, .secureTextField, .unknown:
            .valueReplacement
        }
    }

    private func resolveContext(includeTreeDiagnostic: Bool = false) -> AXFocusedElementSnapshot? {
        guard let snapshot = focusedElementResolver.resolveFocusedElement(
            includeTreeDiagnostic: includeTreeDiagnostic
        ) else {
            return nil
        }
        appModel.focusedElementDiagnosticSummary = snapshot.diagnostic.summary

        return snapshot
    }

    private func captureLearningCandidateIfEligible(
        request: CorrectionRequest,
        currentLayout: KeyboardLayout
    ) {
        let context = request.context
        guard request.source == .autoWordBoundary,
              appModel.autoFixEnabled,
              context.isSecureInput == false,
              context.isPasswordLike == false,
              context.isTerminalLike == false,
              context.supportsWritableAXText,
              context.supportsSelectionRange,
              NSWorkspace.shared.frontmostApplication?.bundleIdentifier == context.frontmostBundleID,
              let token = request.observedToken,
              let entry = inferenceEngine.learningCandidate(for: token, currentLayout: currentLayout),
              learningCandidatePresentationPolicy.shouldPresent(entry)
        else {
            return
        }

        appModel.pendingLearningCandidate = PendingLearningCandidate(
            entry: entry,
            frontmostBundleID: context.frontmostBundleID,
            expiresAt: Date().addingTimeInterval(AppConstants.learningCandidateLifetime)
        )
    }

    private func synchronizeLearningCandidate(with context: AppContext) {
        guard let candidate = appModel.pendingLearningCandidate else {
            return
        }

        if candidate.isExpired
            || candidate.frontmostBundleID != context.frontmostBundleID
            || context.isSecureInput
            || context.isPasswordLike
            || context.isTerminalLike {
            appModel.pendingLearningCandidate = nil
        }
    }

    private func refreshLearnedCorrections() {
        appModel.learnedCorrections = learnedCorrectionStore.entries()
    }

    private func preferredInputSourceID(for layout: KeyboardLayout) -> String {
        appModel.preferredInputSourceIDs[layout]
            ?? inputSourceController.availableSourceOptions().first(where: { $0.keyboardLayout == layout })?.sourceID
            ?? {
                switch layout {
                case .usEnglish: AppConstants.usEnglishSourceID
                case .russian: AppConstants.russianSourceID
                case .ukrainian: AppConstants.ukrainianSourceID
                }
            }()
    }

    private func decisionTargetsParticipatingLayout(_ decision: CorrectionDecision) -> Bool {
        switch decision {
        case let .switchOnly(targetLayout, _):
            appModel.participatingLayouts.contains(targetLayout)
        case let .rewriteAndMaybeSwitch(_, targetLayout, _, _):
            appModel.participatingLayouts.contains(targetLayout)
        case .ignore, .blocked:
            true
        }
    }

    private func redactedTokenSummary(_ token: String, currentLayout: KeyboardLayout?) -> String {
        let latinCount = token.unicodeScalars.filter {
            CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ").contains($0)
        }.count
        let russianCount = token.unicodeScalars.filter {
            CharacterSet(charactersIn: "абвгдеёжзийклмнопрстуфхцчшщъыьэюяАБВГДЕЁЖЗИЙКЛМНОПРСТУФХЦЧШЩЪЫЬЭЮЯ").contains($0)
        }.count
        let dictionaryHit = diagnosticDictionaryStore.lookup(token, currentLayout: currentLayout) != nil
        return "length=\(token.count) latin=\(latinCount) russian=\(russianCount) dictionaryHit=\(dictionaryHit)"
    }

    private func record(decision: CorrectionDecision, request: CorrectionRequest) {
        diagnosticsLogger.log(
            decision: decision,
            request: request,
            focusedAXSummary: appModel.focusedElementDiagnosticSummary
        )
        appModel.updateDiagnostics(diagnosticsLogger.events)
    }

    private func playCorrectionSoundIfEnabled() {
        guard CorrectionFeedbackPolicy.shouldPlaySuccessSound(
            didRewriteText: true,
            soundFeedbackEnabled: appModel.soundFeedbackEnabled
        ) else {
            return
        }

        soundFeedbackPlayer.playCorrectionSuccess()
    }
}
