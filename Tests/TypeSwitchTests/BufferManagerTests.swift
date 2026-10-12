import Testing
@testable import TypeSwitchApp

@Test
func bufferTracksNormalTypingAndBoundary() {
    var manager = BufferManager()
    _ = manager.consume(.text("g"))
    _ = manager.consume(.text("h"))
    let outcome = manager.consume(.delimiter(" "))
    #expect(outcome.completedToken == "gh")
    #expect(manager.currentToken.isEmpty)
}

@Test
func bufferKeepsWrongLayoutLetterPunctuationUntilWhitespaceBoundary() {
    var manager = BufferManager()
    _ = manager.consume(.text("["))
    _ = manager.consume(.text("f"))
    _ = manager.consume(.text("q"))
    let outcome = manager.consume(.delimiter(" "))
    #expect(outcome.completedToken == "[fq")
    #expect(manager.currentToken.isEmpty)
}

@Test
func bufferCompletesTokenWithAmbiguousTrailingPunctuationOnWhitespace() {
    var manager = BufferManager()
    _ = manager.consume(.text("g"))
    _ = manager.consume(.text("h"))
    _ = manager.consume(.text("."))
    let outcome = manager.consume(.delimiter(" "))
    #expect(outcome.completedToken == "gh.")
    #expect(manager.currentToken.isEmpty)
}

@Test
func backspaceUpdatesCurrentToken() {
    var manager = BufferManager()
    _ = manager.consume(.text("g"))
    _ = manager.consume(.text("h"))
    _ = manager.consume(.backspace)
    #expect(manager.currentToken == "g")
}

@Test
func navigationResetsBuffer() {
    var manager = BufferManager()
    _ = manager.consume(.text("g"))
    let outcome = manager.consume(.navigation)
    #expect(outcome.currentToken.isEmpty)
}

@Test
func pasteResetsBuffer() {
    var manager = BufferManager()
    _ = manager.consume(.text("g"))
    let outcome = manager.consume(.paste)
    #expect(outcome.currentToken.isEmpty)
}
