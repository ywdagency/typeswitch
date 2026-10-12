import Foundation

struct DiagnosticEvent: Equatable, Identifiable {
    enum DecisionKind: String, Equatable {
        case ignore
        case switchOnly
        case rewrite
        case blocked
    }

    enum ConfidenceBucket: String, Equatable {
        case none
        case low
        case medium
        case high
    }

    let id = UUID()
    let timestamp: Date
    let source: CorrectionRequest.Source
    let decisionKind: DecisionKind
    let confidenceBucket: ConfidenceBucket
    let frontmostBundleID: String
    let blockedReason: BlockedReason?
    let focusedAXSummary: String?
}

@MainActor
final class DiagnosticsLogger {
    private(set) var events: [DiagnosticEvent] = []
    private let fileWriter: DiagnosticFileWriting

    init(fileWriter: DiagnosticFileWriting = LocalDiagnosticFileWriter()) {
        self.fileWriter = fileWriter
    }

    func log(decision: CorrectionDecision, request: CorrectionRequest, focusedAXSummary: String? = nil) {
        let event = DiagnosticEvent(
            timestamp: Date(),
            source: request.source,
            decisionKind: kind(for: decision),
            confidenceBucket: bucket(for: decision.confidence),
            frontmostBundleID: request.context.frontmostBundleID,
            blockedReason: blockedReason(for: decision),
            focusedAXSummary: focusedAXSummary
        )
        events.insert(event, at: 0)
        events = Array(events.prefix(50))
        fileWriter.append(event: event, context: request.context)
    }

    func logFocusDiagnostic(summary: String) {
        fileWriter.appendFocusDiagnostic(summary: summary)
    }

    func logTrace(_ summary: String) {
        fileWriter.appendTrace(summary: summary)
    }

    private func kind(for decision: CorrectionDecision) -> DiagnosticEvent.DecisionKind {
        switch decision {
        case .ignore:
            .ignore
        case .switchOnly:
            .switchOnly
        case .rewriteAndMaybeSwitch:
            .rewrite
        case .blocked:
            .blocked
        }
    }

    private func bucket(for confidence: Double?) -> DiagnosticEvent.ConfidenceBucket {
        guard let confidence else {
            return .none
        }

        switch confidence {
        case ..<0.70:
            return .low
        case ..<0.85:
            return .medium
        default:
            return .high
        }
    }

    private func blockedReason(for decision: CorrectionDecision) -> BlockedReason? {
        if case let .blocked(reason) = decision {
            return reason
        }
        return nil
    }
}

protocol DiagnosticFileWriting {
    func append(event: DiagnosticEvent, context: AppContext)
    func appendFocusDiagnostic(summary: String)
    func appendTrace(summary: String)
}

struct LocalDiagnosticFileWriter: DiagnosticFileWriting {
    private let fileURL: URL?
    private let formatter: ISO8601DateFormatter

    init(fileManager: FileManager = .default) {
        formatter = ISO8601DateFormatter()
        guard let directory = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("TypeSwitch", isDirectory: true)
        else {
            fileURL = nil
            return
        }

        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        fileURL = directory.appendingPathComponent("diagnostics.log")
    }

    func append(event: DiagnosticEvent, context: AppContext) {
        let blocked = event.blockedReason?.rawValue ?? "none"
        let ax = event.focusedAXSummary ?? "none"
        appendLine(
            [
                formatter.string(from: event.timestamp),
                "source=\(event.source.rawValue)",
                "decision=\(event.decisionKind.rawValue)",
                "confidence=\(event.confidenceBucket.rawValue)",
                "blocked=\(blocked)",
                "bundle=\(context.frontmostBundleID)",
                "control=\(context.controlKind.rawValue)",
                "secure=\(context.isSecureInput)",
                "password=\(context.isPasswordLike)",
                "terminal=\(context.isTerminalLike)",
                "writableAX=\(context.supportsWritableAXText)",
                "selection=\(context.supportsSelectionRange)",
                "ax=\(ax)"
            ].joined(separator: " | ")
        )
    }

    func appendFocusDiagnostic(summary: String) {
        appendLine("\(formatter.string(from: Date())) | focus | ax=\(summary)")
    }

    func appendTrace(summary: String) {
        appendLine("\(formatter.string(from: Date())) | trace | \(summary)")
    }

    private func appendLine(_ line: String) {
        guard let fileURL, let data = (line + "\n").data(using: .utf8) else {
            return
        }

        if FileManager.default.fileExists(atPath: fileURL.path) == false {
            FileManager.default.createFile(atPath: fileURL.path, contents: nil)
        }

        guard let handle = try? FileHandle(forWritingTo: fileURL) else {
            return
        }

        defer { try? handle.close() }
        _ = try? handle.seekToEnd()
        _ = try? handle.write(contentsOf: data)
    }
}
