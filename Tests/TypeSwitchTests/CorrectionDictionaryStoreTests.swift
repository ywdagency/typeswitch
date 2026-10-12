import Testing
@testable import TypeSwitchApp

struct DictionaryLookupCase: Sendable, CustomTestStringConvertible {
    let input: String
    let expected: String

    var testDescription: String { "\(input) → \(expected)" }
}

@Test
func dictionaryFindsRussianWrongLayoutWord() {
    let store = CorrectionDictionaryStore()
    let entry = store.lookup("ghbdtn")

    #expect(entry?.correctToken == "привет")
    #expect(entry?.targetLayout == .russian)
    #expect(entry?.sourceLayout == .usEnglish)
    #expect(entry?.layoutPair == .usRussian)
    #expect(entry?.language == .russian)
}

@Test(arguments: [
    DictionaryLookupCase(input: "lf", expected: "да"),
    DictionaryLookupCase(input: "gj", expected: "по"),
    DictionaryLookupCase(input: "f", expected: "а"),
    DictionaryLookupCase(input: "ns", expected: "ты"),
    DictionaryLookupCase(input: "Ns", expected: "Ты"),
    DictionaryLookupCase(input: "xnj", expected: "что"),
    DictionaryLookupCase(input: "gjxtve", expected: "почему"),
    DictionaryLookupCase(input: "Cutythbheq", expected: "Сгенерируй"),
    DictionaryLookupCase(input: "[fq", expected: "хай")
])
func dictionaryFindsShortRussianWrongLayoutWords(testCase: DictionaryLookupCase) {
    let store = CorrectionDictionaryStore()
    #expect(store.lookup(testCase.input)?.correctToken == testCase.expected)
}

@Test(arguments: [
    DictionaryLookupCase(input: "d", expected: "в"),
    DictionaryLookupCase(input: "dj", expected: "во"),
    DictionaryLookupCase(input: "yf", expected: "на"),
    DictionaryLookupCase(input: "pf", expected: "за"),
    DictionaryLookupCase(input: "r", expected: "к"),
    DictionaryLookupCase(input: "rj", expected: "ко"),
    DictionaryLookupCase(input: "c", expected: "с"),
    DictionaryLookupCase(input: "cj", expected: "со"),
    DictionaryLookupCase(input: "e", expected: "у"),
    DictionaryLookupCase(input: "j", expected: "о"),
    DictionaryLookupCase(input: "j,", expected: "об"),
    DictionaryLookupCase(input: "j,j", expected: "обо"),
    DictionaryLookupCase(input: "jn", expected: "от"),
    DictionaryLookupCase(input: "lj", expected: "до"),
    DictionaryLookupCase(input: "bp", expected: "из"),
    DictionaryLookupCase(input: "gjl", expected: "под"),
    DictionaryLookupCase(input: "yfl", expected: "над"),
    DictionaryLookupCase(input: "ghj", expected: "про"),
    DictionaryLookupCase(input: "ghb", expected: "при"),
    DictionaryLookupCase(input: ",tp", expected: "без"),
    DictionaryLookupCase(input: "lkz", expected: "для"),
    DictionaryLookupCase(input: "gthtl", expected: "перед"),
    DictionaryLookupCase(input: "xthtp", expected: "через")
])
func dictionaryFindsCommonRussianPrepositions(testCase: DictionaryLookupCase) {
    let store = CorrectionDictionaryStore()
    #expect(store.lookup(testCase.input)?.correctToken == testCase.expected)
}

@Test
func dictionaryFindsEnglishWrongLayoutWordFromRussianLayout() {
    let store = CorrectionDictionaryStore()
    let entry = store.lookup("руддщ")

    #expect(entry?.correctToken == "hello")
    #expect(entry?.targetLayout == .usEnglish)
    #expect(entry?.sourceLayout == .russian)
    #expect(entry?.layoutPair == .usRussian)
    #expect(entry?.language == .english)
}

@Test
func dictionaryLookupUsesCurrentLayoutPair() {
    let store = CorrectionDictionaryStore()

    let russianEntry = store.lookup("руддщ", currentLayout: .russian)

    #expect(russianEntry?.correctToken == "hello")
    #expect(russianEntry?.sourceLayout == .russian)
    #expect(russianEntry?.layoutPair == .usRussian)
    #expect(store.lookup("ghbdtn", currentLayout: .russian) == nil)
    #expect(store.lookup("руддщ", currentLayout: .usEnglish) == nil)
    #expect(store.lookup("ghbdtn", currentLayout: .usEnglish)?.correctToken == "привет")
}

@Test
func dictionaryPreservesLeadingCapitalization() {
    let store = CorrectionDictionaryStore()
    #expect(store.lookup("Ghbdtn")?.correctToken == "Привет")
}

@Test
func builtInDictionaryHasBasicRussianCoverage() {
    let mapper = LayoutMapper()
    let store = CorrectionDictionaryStore(mapper: mapper)

    #expect(store.count(for: .russian) >= 175_000)

    #expect(store.lookup(mapper.mapToEnglish("работа"))?.correctToken == "работа")
    #expect(store.lookup(mapper.mapToEnglish("вопрос"))?.correctToken == "вопрос")
    #expect(store.lookup(mapper.mapToEnglish("проверить"))?.correctToken == "проверить")
    #expect(store.lookup(mapper.mapToEnglish("переключается"))?.correctToken == "переключается")
    #expect(store.lookup(mapper.mapToEnglish("разрешения"))?.correctToken == "разрешения")
    #expect(store.lookup(mapper.mapToEnglish("оптимизировать"))?.correctToken == "оптимизировать")
    #expect(store.lookup(mapper.mapToEnglish("человек"))?.correctToken == "человек")
    #expect(store.lookup(mapper.mapToEnglish("быстропротекающий"))?.correctToken == "быстропротекающий")
    #expect(store.lookup("ghbdsn") == nil)
}

@Test
func builtInDictionaryHasExpandedEnglishCoverage() {
    let mapper = LayoutMapper()
    let store = CorrectionDictionaryStore(mapper: mapper)

    #expect(store.count(for: .english) >= 65_000)
    #expect(store.lookup(mapper.mapToRussian("keyboard"))?.correctToken == "keyboard")
    #expect(store.lookup(mapper.mapToRussian("diagnostics"))?.correctToken == "diagnostics")
    #expect(store.lookup(mapper.mapToRussian("default"))?.correctToken == "default")
    #expect(store.lookup(mapper.mapToRussian("beautiful"))?.correctToken == "beautiful")
    #expect(store.lookup(mapper.mapToRussian("interoperability"))?.correctToken == "interoperability")
    #expect(store.lookup("скнзещ")?.correctToken == "crypto")
    #expect(store.lookup("ФЗШ", currentLayout: .russian)?.correctToken == "API")
    #expect(store.lookup("Ш")?.correctToken == "I")
    #expect(store.lookup("Шэь")?.correctToken == "I'm")
    #expect(store.lookup("рун")?.correctToken == "hey")
    #expect(store.lookup("щлфн")?.correctToken == "okay")
    #expect(store.lookup("щлун")?.correctToken == "okey")
    #expect(store.lookup("ГЫ")?.correctToken == "US")
    #expect(store.lookup("ыщ", currentLayout: .russian)?.correctToken == "so")
    #expect(store.lookup("дщпщ")?.correctToken == "logo")
    #expect(store.lookup("ергьитфшд")?.correctToken == "thumbnail")
    #expect(store.lookup("ергьитфшды")?.correctToken == "thumbnails")
    #expect(store.lookup("Ергьитфшды")?.correctToken == "Thumbnails")
    #expect(store.lookup("-Ю")?.correctToken == "->")
    #expect(store.lookup("ьфеукшфды")?.correctToken == "materials")
    #expect(store.lookup("Ерфеэы")?.correctToken == "That's")
}

@Test
func builtInDictionaryHasUkrainianCoverageAndPreservesAmbiguity() {
    let store = CorrectionDictionaryStore()

    #expect(store.count(for: .ukrainian) >= 290_000)
    #expect(store.contains("український", in: .ukrainian))
    for noise in ["щт", "туц", "філ", "філі", "уес", "рщт", "ьуп", "рьщ", "зоі"] {
        #expect(store.contains(noise, in: .ukrainian) == false)
    }
    #expect(store.contains("on", in: .usEnglish))
    #expect(store.contains("український", in: .russian) == false)
    #expect(store.contains("слово", in: .ukrainian))
    #expect(store.contains("слово", in: .russian))
    #expect(store.dominantRussianUkrainianLayout(for: "привет") == nil)
    #expect(store.dominantRussianUkrainianLayout(for: "як") == .ukrainian)
    #expect(store.dominantRussianUkrainianLayout(for: "слово") == nil)
}
