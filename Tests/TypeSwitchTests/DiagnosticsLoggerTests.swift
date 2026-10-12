import Testing
@testable import TypeSwitchApp

@MainActor
@Test
func diagnosticsStayRedacted() {
    let writer = CapturingDiagnosticFileWriter()
    let logger = DiagnosticsLogger(fileWriter: writer)
    let request = CorrectionRequest(
        source: .manualLastWord,
        observedToken: "ghbdtn",
        selectionMode: .lastWord,
        context: AppContext(
            frontmostBundleID: "com.apple.Safari",
            frontmostAppName: "Safari",
            controlKind: .browserTextArea,
            isSecureInput: false,
            isPasswordLike: false,
            isTerminalLike: false,
            supportsWritableAXText: true,
            supportsSelectionRange: true
        )
    )

    logger.log(
        decision: .rewriteAndMaybeSwitch(replacement: "привет", targetLayout: .russian, reason: "test", confidence: 0.9),
        request: request
    )

    #expect(logger.events.count == 1)
    #expect(logger.events[0].frontmostBundleID == "com.apple.Safari")
    #expect(logger.events[0].blockedReason == nil)
    #expect(writer.lines.joined().contains("ghbdtn") == false)
    #expect(writer.lines.joined().contains("привет") == false)
}

private final class CapturingDiagnosticFileWriter: DiagnosticFileWriting {
    var lines: [String] = []

    func append(event: DiagnosticEvent, context: AppContext) {
        lines.append(
            [
                "source=\(event.source.rawValue)",
                "decision=\(event.decisionKind.rawValue)",
                "bundle=\(context.frontmostBundleID)",
                "blocked=\(event.blockedReason?.rawValue ?? "none")",
                "ax=\(event.focusedAXSummary ?? "none")"
            ].joined(separator: " | ")
        )
    }

    func appendFocusDiagnostic(summary: String) {
        lines.append("focus | ax=\(summary)")
    }

    func appendTrace(summary: String) {
        lines.append("trace | \(summary)")
    }
}
