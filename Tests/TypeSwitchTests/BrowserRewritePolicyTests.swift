import Testing
@testable import TypeSwitchApp

@Test
func chromeBrowserControlsUseBoundedFallbackWithoutAxMutation() {
    #expect(AXRewriteRoutingPolicy.requiresBoundedFallback(
        bundleID: "com.google.Chrome",
        controlKind: .browserTextArea
    ))
    #expect(AXRewriteRoutingPolicy.requiresBoundedFallback(
        bundleID: "com.google.Chrome.canary",
        controlKind: .browserContentEditable
    ))
    #expect(AXRewriteRoutingPolicy.requiresBoundedFallback(
        bundleID: "com.google.Chrome",
        controlKind: .nativeTextInput
    ) == false)
    #expect(AXRewriteRoutingPolicy.requiresBoundedFallback(
        bundleID: "com.apple.Safari",
        controlKind: .browserTextArea
    ) == false)
}
