import Testing
@testable import TypeSwitchApp

@Test
func russianInflectionRequiresBaseFlagAndCondition() {
    let dictionary = RussianInflectionDictionary(
        baseLines: ["копирование\tJ", "море\tJ", "поле\tK"],
        ruleLines: ["J\tе\tем\tие"]
    )

    #expect(dictionary.contains("копированием"))
    #expect(dictionary.contains("морем") == false) // Wrong rule condition.
    #expect(dictionary.contains("полем") == false) // Wrong entry flag.
    #expect(dictionary.contains("выдумыванием") == false) // Missing base.
    #expect(dictionary.contains("копированиеом") == false)
    #expect(dictionary.contains("копированием!") == false)
    #expect(dictionary.contains("копированиeм") == false) // Latin e.
}

@Test
func russianInflectionHandlesEmptyEndingsAndStemChangesWithoutChaining() {
    let dictionary = RussianInflectionDictionary(
        baseLines: ["стол\tK", "блюдо\tK", "замок\tO"],
        ruleLines: ["K\t0\tами\t[^ейоь]", "K\tо\t0\t[дгств]о", "O\tок\tком\tок"]
    )

    #expect(dictionary.contains("столами"))
    #expect(dictionary.contains("блюд"))
    #expect(dictionary.contains("замком"))
    #expect(dictionary.contains("столамиами") == false)
    #expect(dictionary.contains("замоком") == false)
}
