import Foundation

struct CorrectionRequest: Equatable {
    enum Source: String, Equatable {
        case manualLastWord
        case manualSelection
        case autoWordBoundary
    }

    enum SelectionMode: Equatable {
        case none
        case lastWord
        case selectedText
    }

    let source: Source
    let observedToken: String?
    let trailingDelimiter: String?
    let selectionMode: SelectionMode
    let context: AppContext

    init(
        source: Source,
        observedToken: String?,
        trailingDelimiter: String? = nil,
        selectionMode: SelectionMode,
        context: AppContext
    ) {
        self.source = source
        self.observedToken = observedToken
        self.trailingDelimiter = trailingDelimiter
        self.selectionMode = selectionMode
        self.context = context
    }
}
