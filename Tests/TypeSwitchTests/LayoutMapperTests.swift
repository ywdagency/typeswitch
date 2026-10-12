import Testing
@testable import TypeSwitchApp

@Test
func mapsEnglishTokenToRussian() {
    let mapper = LayoutMapper()
    #expect(mapper.mapToRussian("ghbdtn") == "привет")
}

@Test
func mapsRussianTokenToEnglish() {
    let mapper = LayoutMapper()
    #expect(mapper.mapToEnglish("руддщ") == "hello")
}

@Test
func preservesUppercaseAndPunctuation() {
    let mapper = LayoutMapper()
    #expect(mapper.mapToRussian("Ghbdtn!") == "Привет!")
}

@Test
func mapsShiftedPunctuationBetweenEnglishAndRussianLayouts() {
    let mapper = LayoutMapper()
    #expect(mapper.mapToRussian("->") == "-Ю")
    #expect(mapper.mapToEnglish("-Ю") == "->")
}

@Test
func mapsPhysicalKeysBetweenUkrainianAndRussianLayouts() {
    let mapper = LayoutMapper()

    #expect(mapper.map("грізть", from: .ukrainian, to: .russian) == "грызть")
    #expect(mapper.map("ті", from: .ukrainian, to: .russian) == "ты")
    #expect(mapper.map("грызть", from: .russian, to: .ukrainian) == "грізть")
}

@Test
func leavesUnsupportedCharactersUntouched() {
    let mapper = LayoutMapper()
    #expect(mapper.mapToRussian("123") == "123")
}
