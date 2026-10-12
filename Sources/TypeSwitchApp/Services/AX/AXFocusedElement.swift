import AppKit
import ApplicationServices
import Carbon
import Foundation

struct AXFocusedElementSnapshot {
    let context: AppContext
    let element: AXElementProtocol
    let diagnostic: AXFocusedElementDiagnostic
}

struct AXFocusedElementDiagnostic: Equatable {
    let summary: String
}

protocol FocusedElementResolving {
    func resolveFocusedElement(includeTreeDiagnostic: Bool) -> AXFocusedElementSnapshot?
}

extension FocusedElementResolving {
    func resolveFocusedElement() -> AXFocusedElementSnapshot? {
        resolveFocusedElement(includeTreeDiagnostic: false)
    }
}

struct AXFocusedElementResolver: FocusedElementResolving {
    func resolveFocusedElement(includeTreeDiagnostic: Bool) -> AXFocusedElementSnapshot? {
        guard let frontmostApp = NSWorkspace.shared.frontmostApplication,
              let bundleID = frontmostApp.bundleIdentifier
        else {
            return nil
        }

        guard let focusedObject = focusedElementObject(for: frontmostApp) else {
            return nil
        }

        let focusedElement = SystemAXElement(axElement: focusedObject as! AXUIElement)
        let searchResult = focusedElement.bestWritableTextCandidate(maxDepth: 6, maxVisited: 200)
        let axElement = searchResult?.element ?? focusedElement
        let context = AppContext(
            frontmostBundleID: bundleID,
            frontmostAppName: frontmostApp.localizedName ?? bundleID,
            controlKind: classifyControlKind(bundleID: bundleID, element: axElement),
            isSecureInput: IsSecureEventInputEnabled(),
            isPasswordLike: isPasswordLike(axElement),
            isTerminalLike: isTerminalBundleID(bundleID),
            supportsWritableAXText: axElement.isValueSettable || axElement.isSelectedTextSettable,
            supportsSelectionRange: (try? axElement.selectedTextRange()) != nil
        )
        let diagnostic = focusedElement.diagnostic(
            appName: frontmostApp.localizedName ?? bundleID,
            bundleID: bundleID,
            candidate: searchResult,
            includeTree: includeTreeDiagnostic
        )

        return AXFocusedElementSnapshot(context: context, element: axElement, diagnostic: diagnostic)
    }

    private func focusedElementObject(for frontmostApp: NSRunningApplication) -> CFTypeRef? {
        let systemWide = AXUIElementCreateSystemWide()
        if let focusedObject = axElementAttribute(systemWide, kAXFocusedUIElementAttribute) {
            return focusedObject
        }

        let appElement = AXUIElementCreateApplication(frontmostApp.processIdentifier)
        if let focusedObject = axElementAttribute(appElement, kAXFocusedUIElementAttribute) {
            return focusedObject
        }

        return axElementAttribute(appElement, kAXFocusedWindowAttribute)
    }

    private func axElementAttribute(_ element: AXUIElement, _ attribute: String) -> CFTypeRef? {
        var object: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, attribute as CFString, &object)
        guard result == .success, let object, CFGetTypeID(object) == AXUIElementGetTypeID() else {
            return nil
        }
        return object
    }

    private func classifyControlKind(bundleID: String, element: SystemAXElement) -> AppContext.ControlKind {
        if isTerminalBundleID(bundleID) {
            return .terminal
        }

        if isPasswordLike(element) {
            return .secureTextField
        }

        let role = element.role ?? ""
        if bundleID == "com.apple.Safari" || bundleID == "com.google.Chrome" {
            if role == kAXTextFieldRole as String {
                return .browserTextInput
            }
            if role == kAXTextAreaRole as String {
                return .browserTextArea
            }
            return .browserContentEditable
        }

        if role == kAXTextFieldRole as String || role == kAXTextAreaRole as String || role == kAXComboBoxRole as String {
            return .nativeTextInput
        }

        return .unknown
    }

    private func isPasswordLike(_ element: SystemAXElement) -> Bool {
        let values = [element.role, element.subrole]
            .compactMap { $0?.lowercased() }
        return values.contains(where: { $0.contains("secure") || $0.contains("password") })
    }

    private func isTerminalBundleID(_ bundleID: String) -> Bool {
        Set(["com.apple.Terminal", "com.googlecode.iterm2"]).contains(bundleID)
    }
}

final class SystemAXElement: AXElementProtocol {
    let axElement: AXUIElement

    init(axElement: AXUIElement) {
        self.axElement = axElement
    }

    var role: String? {
        stringAttribute(named: kAXRoleAttribute)
    }

    var subrole: String? {
        stringAttribute(named: kAXSubroleAttribute)
    }

    var isValueSettable: Bool {
        isAttributeSettable(kAXValueAttribute as CFString)
    }

    var isSelectedTextSettable: Bool {
        isAttributeSettable(kAXSelectedTextAttribute as CFString)
    }

    var isSelectedTextRangeSettable: Bool {
        isAttributeSettable(kAXSelectedTextRangeAttribute as CFString)
    }

    private func isAttributeSettable(_ attribute: CFString) -> Bool {
        var settable = DarwinBoolean(false)
        let result = AXUIElementIsAttributeSettable(axElement, attribute, &settable)
        return result == .success && settable.boolValue
    }

    var children: [SystemAXElement] {
        let childAttributeNames = [
            kAXFocusedUIElementAttribute,
            kAXChildrenAttribute,
            kAXVisibleChildrenAttribute,
            kAXContentsAttribute,
            kAXSelectedChildrenAttribute,
            "AXChildrenInNavigationOrder",
            "AXTabs",
            "AXRows",
            "AXColumns",
            "AXVisibleCells",
            "AXLinkedUIElements"
        ]
        var seenHashes = Set<CFHashCode>()
        return childAttributeNames.flatMap { childElements(from: $0 as String) }
            .filter { child in
                let hash = CFHash(child.axElement)
                guard seenHashes.contains(hash) == false else {
                    return false
                }
                seenHashes.insert(hash)
                return true
            }
    }

    private func childElements(from attributeName: String) -> [SystemAXElement] {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(axElement, attributeName as CFString, &value)
        guard result == .success, let value else {
            return []
        }

        if CFGetTypeID(value) == AXUIElementGetTypeID() {
            return [SystemAXElement(axElement: value as! AXUIElement)]
        }

        guard let rawChildren = value as? [AXUIElement] else {
            return []
        }

        return rawChildren.map { SystemAXElement(axElement: $0) }
    }

    func stringValue() throws -> String? {
        stringAttribute(named: kAXValueAttribute)
    }

    func selectedText() throws -> String? {
        stringAttribute(named: kAXSelectedTextAttribute)
    }

    func selectedTextRange() throws -> CFRange? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(axElement, kAXSelectedTextRangeAttribute as CFString, &value)
        guard result == .success else {
            return nil
        }

        guard let value, CFGetTypeID(value) == AXValueGetTypeID() else {
            return nil
        }

        let axValue = value as! AXValue
        guard AXValueGetType(axValue) == .cfRange else {
            return nil
        }

        var range = CFRange()
        AXValueGetValue(axValue, .cfRange, &range)
        return range
    }

    func setStringValue(_ value: String) throws {
        guard isValueSettable else {
            throw AXElementError.notWritable
        }

        let result = AXUIElementSetAttributeValue(axElement, kAXValueAttribute as CFString, value as CFTypeRef)
        guard result == .success else {
            throw AXElementError.notWritable
        }
    }

    func setSelectedText(_ value: String) throws {
        guard isSelectedTextSettable else {
            throw AXElementError.unsupported
        }

        let result = AXUIElementSetAttributeValue(
            axElement,
            kAXSelectedTextAttribute as CFString,
            value as CFTypeRef
        )
        guard result == .success else {
            throw AXElementError.unsupported
        }
    }

    func setSelectedTextRange(_ range: CFRange) throws {
        var mutableRange = range
        guard let axValue = AXValueCreate(.cfRange, &mutableRange) else {
            throw AXElementError.invalidRange
        }

        let result = AXUIElementSetAttributeValue(axElement, kAXSelectedTextRangeAttribute as CFString, axValue)
        guard result == .success else {
            throw AXElementError.invalidRange
        }
    }

    private func stringAttribute(named name: String) -> String? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(axElement, name as CFString, &value)
        guard result == .success else {
            return nil
        }

        return value as? String
    }

    fileprivate func bestWritableTextCandidate(maxDepth: Int, maxVisited: Int) -> WritableTextCandidate? {
        var queue: [(element: SystemAXElement, depth: Int)] = [(self, 0)]
        var visited = 0
        var fallbackCandidate: WritableTextCandidate?

        while queue.isEmpty == false, visited < maxVisited {
            let candidate = queue.removeFirst()
            visited += 1

            if candidate.element.isSafeWritableTextCandidate {
                let writableCandidate = WritableTextCandidate(element: candidate.element, depth: candidate.depth, visitedCount: visited)
                if candidate.element.hasNonEmptyStringValue {
                    return writableCandidate
                }
                fallbackCandidate = fallbackCandidate ?? writableCandidate
            }

            guard candidate.depth < maxDepth else {
                continue
            }

            queue.append(contentsOf: candidate.element.children.map { ($0, candidate.depth + 1) })
        }

        return fallbackCandidate
    }

    fileprivate func diagnostic(
        appName: String,
        bundleID: String,
        candidate: WritableTextCandidate?,
        includeTree: Bool
    ) -> AXFocusedElementDiagnostic {
        let focusedSummary = redactedAXSummary(prefix: "focused", depth: 0)
        let candidateSummary = candidate.map {
            $0.element.redactedAXSummary(prefix: "candidate", depth: $0.depth) + " visited=\($0.visitedCount)"
        } ?? "candidate=none"
        let treeSummary = includeTree
            ? " | tree=\(redactedTreeSummary(maxDepth: 3, maxVisited: 24))"
            : ""
        return AXFocusedElementDiagnostic(
            summary: "\(appName) (\(bundleID)) | \(focusedSummary) | \(candidateSummary)\(treeSummary)"
        )
    }

    private func redactedAXSummary(prefix: String, depth: Int) -> String {
        let role = role ?? "nil"
        let subrole = subrole ?? "nil"
        return "\(prefix)[depth=\(depth)] role=\(role) subrole=\(subrole) settable=\(isValueSettable) selectedTextSettable=\(isSelectedTextSettable) selectedTextRangeSettable=\(isSelectedTextRangeSettable) valueLength=\(stringValueLength) selection=\(hasSelectionRange) children=\(children.count)"
    }

    private func redactedTreeSummary(maxDepth: Int, maxVisited: Int) -> String {
        var queue: [(element: SystemAXElement, depth: Int)] = [(self, 0)]
        var visited = 0
        var summaries: [String] = []
        var seenHashes = Set<CFHashCode>()

        while queue.isEmpty == false, visited < maxVisited {
            let current = queue.removeFirst()
            let hash = CFHash(current.element.axElement)
            guard seenHashes.contains(hash) == false else {
                continue
            }
            seenHashes.insert(hash)
            visited += 1
            summaries.append(current.element.redactedAXSummary(prefix: "node", depth: current.depth))

            guard current.depth < maxDepth else {
                continue
            }
            queue.append(contentsOf: current.element.children.map { ($0, current.depth + 1) })
        }

        return summaries.joined(separator: " > ")
    }

    private var hasNonEmptyStringValue: Bool {
        guard let value = try? stringValue() else {
            return false
        }
        return value.isEmpty == false
    }

    private var stringValueLength: Int {
        guard let value = try? stringValue() else {
            return -1
        }
        return value.utf16.count
    }

    private var hasSelectionRange: Bool {
        (try? selectedTextRange()) != nil
    }

    private var isSafeWritableTextCandidate: Bool {
        guard isValueSettable || isSelectedTextSettable else {
            return false
        }

        guard (try? selectedTextRange()) != nil else {
            return false
        }

        let role = role ?? ""
        if Self.explicitTextRoles.contains(role) {
            return true
        }

        guard Self.containerTextRoles.contains(role) else {
            return false
        }

        guard (try? stringValue()) != nil else {
            return false
        }

        return true
    }

    private static let explicitTextRoles: Set<String> = [
        kAXTextFieldRole as String,
        kAXTextAreaRole as String,
        kAXComboBoxRole as String
    ]

    private static let containerTextRoles: Set<String> = [
        kAXGroupRole as String,
        "AXWebArea"
    ]

    fileprivate struct WritableTextCandidate {
        let element: SystemAXElement
        let depth: Int
        let visitedCount: Int
    }
}
