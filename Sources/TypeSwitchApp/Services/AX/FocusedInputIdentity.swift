import AppKit
import ApplicationServices
import Carbon

final class FocusedInputIdentity: @unchecked Sendable, Equatable {
    private let application: AXUIElement
    private let element: AXUIElement

    private init(application: AXUIElement, element: AXUIElement) {
        self.application = application
        self.element = element
    }

    @MainActor
    static func current() -> FocusedInputIdentity? {
        guard let frontmost = NSWorkspace.shared.frontmostApplication else { return nil }
        let application = AXUIElementCreateApplication(frontmost.processIdentifier)
        guard let focused = focusedElement(in: application) else { return nil }
        return FocusedInputIdentity(application: application, element: focused)
    }

    private static func focusedElement(in application: AXUIElement) -> AXUIElement? {
        elementAttribute(application, kAXFocusedUIElementAttribute)
            ?? elementAttribute(application, kAXFocusedWindowAttribute)
    }

    private static func elementAttribute(_ element: AXUIElement, _ attribute: String) -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXUIElementGetTypeID()
        else { return nil }
        return value as! AXUIElement
    }

    func isCurrent() -> Bool {
        guard IsSecureEventInputEnabled() == false else { return false }
        var frontmost: CFTypeRef?
        guard AXUIElementCopyAttributeValue(application, kAXFrontmostAttribute as CFString, &frontmost) == .success,
              let frontmost, CFGetTypeID(frontmost) == CFBooleanGetTypeID(),
              CFBooleanGetValue((frontmost as! CFBoolean)),
              let focused = Self.focusedElement(in: application)
        else { return false }
        return CFEqual(element, focused)
    }

    static func == (lhs: FocusedInputIdentity, rhs: FocusedInputIdentity) -> Bool {
        CFEqual(lhs.application, rhs.application) && CFEqual(lhs.element, rhs.element)
    }
}
