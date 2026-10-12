import AppKit
import Testing
@testable import TypeSwitchApp

@Test
func statusItemDistinguishesLeftAndRightClicks() {
    #expect(StatusItemClickAction.resolve(eventType: .leftMouseUp) == .showMenu)
    #expect(StatusItemClickAction.resolve(eventType: .rightMouseUp) == .toggleAutoFix)
    #expect(StatusItemClickAction.resolve(eventType: .mouseMoved) == .ignore)
}
