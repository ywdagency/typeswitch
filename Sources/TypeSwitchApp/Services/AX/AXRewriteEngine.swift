import Foundation

enum AXLastWordRewriteStrategy {
    case valueReplacement
    case selectedTextOnly
}

struct AXRewriteEngine {
    @discardableResult
    func replaceSelectedText(in element: AXElementProtocol, replacement: String) throws -> Bool {
        guard element.isValueSettable, element.isSelectedTextRangeSettable else {
            throw AXElementError.notWritable
        }

        guard let value = try element.stringValue(),
              let range = try element.selectedTextRange(),
              range.length > 0,
              let replacementRange = Self.range(from: range, in: value)
        else {
            throw AXElementError.missingSelection
        }

        let updated = value.replacingCharacters(in: replacementRange, with: replacement)
        try element.setStringValue(updated)
        guard try element.stringValue() == updated else {
            throw AXElementError.verificationFailed
        }
        let caretLocation = range.location + replacement.utf16.count
        try setCaret(in: element, location: caretLocation)
        return true
    }

    @discardableResult
    func replaceLastWordAtCaret(in element: AXElementProtocol, replacement: String) throws -> Bool {
        try replaceLastWordAtCaret(
            in: element,
            replacement: replacement,
            observedToken: nil,
            strategy: .valueReplacement
        )
    }

    @discardableResult
    func replaceLastWordAtCaret(
        in element: AXElementProtocol,
        replacement: String,
        observedToken: String?,
        strategy: AXLastWordRewriteStrategy = .valueReplacement
    ) throws -> Bool {
        guard element.isSelectedTextRangeSettable else {
            throw AXElementError.notWritable
        }

        guard element.isValueSettable || strategy == .selectedTextOnly && element.isSelectedTextSettable else {
            throw AXElementError.notWritable
        }

        guard let value = try element.stringValue(),
              let caretRange = try element.selectedTextRange(),
              caretRange.length == 0
        else {
            throw AXElementError.missingSelection
        }

        let replacementRange = Self.lastWordRange(in: value, caretLocation: caretRange.location)
            ?? Self.suffixRange(for: observedToken, in: value)

        guard let replacementRange else {
            throw AXElementError.invalidRange
        }

        if let observedToken,
           value[replacementRange] != observedToken {
            throw AXElementError.staleValue
        }

        let replacementNSRange = NSRange(replacementRange, in: value)
        let updated = value.replacingCharacters(in: replacementRange, with: replacement)
        let caretLocation: Int
        if caretRange.location <= value.utf16.count {
            caretLocation = max(
                0,
                min(
                    updated.utf16.count,
                    caretRange.location + replacement.utf16.count - replacementNSRange.length
                )
            )
        } else {
            caretLocation = updated.utf16.count
        }

        switch strategy {
        case .valueReplacement:
            guard element.isValueSettable else {
                throw AXElementError.notWritable
            }
            try element.setStringValue(updated)
        case .selectedTextOnly:
            guard element.isSelectedTextSettable else {
                throw AXElementError.unsupported
            }
            let originalCaretRange = caretRange
            do {
                try element.setSelectedTextRange(
                    CFRange(location: replacementNSRange.location, length: replacementNSRange.length)
                )
                try element.setSelectedText(replacement)
            } catch {
                try? element.setSelectedTextRange(originalCaretRange)
                throw error
            }
        }

        guard try element.stringValue() == updated else {
            throw AXElementError.verificationFailed
        }
        try setCaret(in: element, location: caretLocation)
        return true
    }

    private func setCaret(in element: AXElementProtocol, location: Int) throws {
        let expectedRange = CFRange(location: location, length: 0)
        try element.setSelectedTextRange(expectedRange)
        guard let actualRange = try element.selectedTextRange(),
              actualRange.location == expectedRange.location,
              actualRange.length == expectedRange.length
        else {
            throw AXElementError.verificationFailed
        }
    }

    static func lastWordRange(in value: String, caretLocation: Int) -> Range<String.Index>? {
        guard caretLocation >= 0, caretLocation <= value.utf16.count else {
            return nil
        }

        guard let caretIndex = String.Index(utf16Offset: caretLocation, in: value).samePosition(in: value) else {
            return nil
        }

        var end = caretIndex
        while end > value.startIndex {
            let previous = value.index(before: end)
            if BufferManager.isWordBoundary(value[previous]) {
                end = previous
            } else {
                break
            }
        }

        guard end > value.startIndex else {
            return nil
        }

        var start = end
        while start > value.startIndex {
            let previous = value.index(before: start)
            if BufferManager.isWordBoundary(value[previous]) {
                break
            }
            start = previous
        }

        guard start < end else {
            return nil
        }

        return start..<end
    }

    static func range(from cfRange: CFRange, in value: String) -> Range<String.Index>? {
        guard cfRange.location >= 0, cfRange.length >= 0 else {
            return nil
        }

        let lower = String.Index(utf16Offset: cfRange.location, in: value)
        let upper = String.Index(utf16Offset: cfRange.location + cfRange.length, in: value)
        guard lower <= upper, upper <= value.endIndex else {
            return nil
        }
        return lower..<upper
    }

    static func suffixRange(for observedToken: String?, in value: String) -> Range<String.Index>? {
        guard let observedToken, observedToken.isEmpty == false else {
            return nil
        }

        var suffixEnd = value.endIndex
        while suffixEnd > value.startIndex {
            let previous = value.index(before: suffixEnd)
            if BufferManager.isWordBoundary(value[previous]) {
                suffixEnd = previous
            } else {
                break
            }
        }

        let candidate = value[..<suffixEnd]
        guard candidate.hasSuffix(observedToken) else {
            return nil
        }

        let lower = value.index(suffixEnd, offsetBy: -observedToken.count)
        return lower..<suffixEnd
    }

    static func redactedLastWordRewriteState(in element: AXElementProtocol, observedToken: String?) -> String {
        let value = (try? element.stringValue()) ?? nil
        let range = (try? element.selectedTextRange()) ?? nil
        let valueLength = value?.utf16.count ?? -1
        let rangeLocation = range?.location ?? -1
        let rangeLength = range?.length ?? -1
        let rangeInBounds = range.map {
            $0.location >= 0 && $0.length >= 0 && ($0.location + $0.length) <= valueLength
        } ?? false
        let suffixMatch = value.map {
            suffixRange(for: observedToken, in: $0) != nil
        } ?? false

        return "valueLength=\(valueLength) caret=\(rangeLocation) selectionLength=\(rangeLength) rangeInBounds=\(rangeInBounds) suffixMatch=\(suffixMatch)"
    }
}
