import Foundation

struct CorrectionDictionaryStore {
    private static let lowercaseEnglishLetters = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz")
    private static let russianLetters = CharacterSet(charactersIn: "абвгдеёжзийклмнопрстуфхцчшщъыьэюя")

    private let mapper: LayoutMapper
    private let learnedStore: LearnedCorrectionStore?
    private let customEntriesByLookupKey: [LookupKey: CorrectionDictionaryEntry]
    private let russianWords: SortedWordList
    private let russianInflections: RussianInflectionDictionary
    private let englishWords: SortedWordList
    private let ukrainianWords: SortedWordList
    private let russianLanguageMarkers: SortedWordList
    private let ukrainianLanguageMarkers: SortedWordList
    private let trustedRussianWords: Set<String>
    private let trustedEnglishWords: Set<String>

    private static let cachedBuiltInWordSets = loadBuiltInWordSets()

    init(
        mapper: LayoutMapper = LayoutMapper(),
        entries: [CorrectionDictionaryEntry]? = nil,
        learnedStore: LearnedCorrectionStore? = nil
    ) {
        self.mapper = mapper
        self.learnedStore = learnedStore
        let sourceEntries = entries ?? []
        self.customEntriesByLookupKey = Dictionary(sourceEntries.map {
            (
                LookupKey(layoutPair: $0.layoutPair, sourceLayout: $0.sourceLayout, wrongToken: $0.wrongToken),
                $0
            )
        }) { first, _ in
            first
        }
        if entries == nil {
            let wordSets = Self.cachedBuiltInWordSets
            self.russianWords = wordSets.russian
            self.russianInflections = wordSets.russianInflections
            self.englishWords = wordSets.english
            self.ukrainianWords = wordSets.ukrainian
            self.russianLanguageMarkers = wordSets.russianMarkers
            self.ukrainianLanguageMarkers = wordSets.ukrainianMarkers
            self.trustedRussianWords = wordSets.trustedRussian
            self.trustedEnglishWords = wordSets.trustedEnglish
        } else {
            self.russianWords = SortedWordList(words: [])
            self.russianInflections = RussianInflectionDictionary()
            self.englishWords = SortedWordList(words: [])
            self.ukrainianWords = SortedWordList(words: [])
            self.russianLanguageMarkers = SortedWordList(words: [])
            self.ukrainianLanguageMarkers = SortedWordList(words: [])
            self.trustedRussianWords = []
            self.trustedEnglishWords = []
        }
    }

    func lookup(_ token: String, currentLayout: KeyboardLayout?) -> CorrectionDictionaryEntry? {
        let normalizedToken = token.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        if let learnedEntry = learnedStore?.lookup(normalizedToken, currentLayout: currentLayout) {
            return CorrectionDictionaryEntry(
                wrongToken: learnedEntry.wrongToken,
                correctToken: correctedCapitalization(for: token, replacement: learnedEntry.correctToken),
                targetLayout: learnedEntry.targetLayout,
                sourceLayout: learnedEntry.sourceLayout,
                layoutPair: learnedEntry.layoutPair,
                language: learnedEntry.language,
                source: learnedEntry.source
            )
        }

        guard let lookupScope = lookupScope(for: currentLayout), lookupScope.isEmpty == false else {
            return nil
        }

        if var customEntry = lookupScope.compactMap({
            customEntriesByLookupKey[
                LookupKey(
                    layoutPair: $0.layoutPair,
                    sourceLayout: $0.sourceLayout,
                    wrongToken: normalizedToken
                )
            ]
        }).first {
            customEntry = entryWithCorrectedCapitalization(customEntry, originalToken: token)
            return customEntry
        }

        guard let entry = builtInEntry(for: token.trimmingCharacters(in: .whitespacesAndNewlines))
            ?? derivedEnglishPluralEntry(for: normalizedToken, lookupScope: lookupScope),
              lookupScope.contains(where: {
                  $0.layoutPair == entry.layoutPair && $0.sourceLayout == entry.sourceLayout
              })
        else {
            return nil
        }
        return entryWithCorrectedCapitalization(entry, originalToken: token)
    }

    private func builtInEntry(for token: String) -> CorrectionDictionaryEntry? {
        let normalizedToken = token.lowercased()
        let russianCandidate = mapper.mapToRussian(token).lowercased()
        let englishCandidate = mapper.mapToEnglish(token).lowercased()

        let exactRussianMatch = russianWords.contains(russianCandidate)
        let inflectedRussianMatch = exactRussianMatch == false && russianInflections.contains(russianCandidate)
            && (ukrainianWords.contains(mapper.map(token, from: .usEnglish, to: .ukrainian).lowercased()) == false
                || (mapper.map(token, from: .usEnglish, to: .ukrainian).lowercased() == russianCandidate
                    && frequencyDominantRussianUkrainianLayout(for: russianCandidate) == .russian))
        let russianMatch = russianCandidate != normalizedToken
            && (exactRussianMatch || inflectedRussianMatch)
            && (trustedRussianWords.contains(russianCandidate)
                || englishWords.contains(normalizedToken) == false)
        let englishMatch = englishCandidate != normalizedToken
            && englishWords.contains(englishCandidate)
            && (trustedEnglishWords.contains(englishCandidate)
                || contains(normalizedToken, in: .russian) == false)

        guard russianMatch != englishMatch else {
            return nil
        }

        if russianMatch {
            return CorrectionDictionaryEntry(
                wrongToken: normalizedToken,
                correctToken: russianCandidate,
                targetLayout: .russian,
                sourceLayout: .usEnglish,
                layoutPair: .usRussian,
                language: .russian,
                source: "built-in"
            )
        }

        return CorrectionDictionaryEntry(
            wrongToken: normalizedToken,
            correctToken: englishCandidate,
            targetLayout: .usEnglish,
            sourceLayout: .russian,
            layoutPair: .usRussian,
            language: .english,
            source: "built-in-russian-layout"
        )
    }

    private func derivedEnglishPluralEntry(
        for normalizedToken: String,
        lookupScope: [(layoutPair: CorrectionDictionaryLayoutPair, sourceLayout: KeyboardLayout)]
    ) -> CorrectionDictionaryEntry? {
        guard lookupScope.contains(where: { $0.layoutPair == .usRussian && $0.sourceLayout == .russian }),
              normalizedToken.rangeOfCharacter(from: Self.russianLetters) != nil
        else {
            return nil
        }

        let candidate = mapper.mapToEnglish(normalizedToken).lowercased()
        guard candidate.count >= 5,
              candidate.unicodeScalars.allSatisfy({ Self.lowercaseEnglishLetters.contains($0) }),
              candidate.hasSuffix("s")
        else {
            return nil
        }

        for singular in englishSingularCandidates(forPlural: candidate) {
            guard englishWords.contains(singular) else {
                continue
            }

            return CorrectionDictionaryEntry(
                wrongToken: normalizedToken,
                correctToken: candidate,
                targetLayout: .usEnglish,
                sourceLayout: .russian,
                layoutPair: .usRussian,
                language: .english,
                source: "derived-english-plural"
            )
        }

        return nil
    }

    private func englishSingularCandidates(forPlural plural: String) -> [String] {
        var candidates: [String] = []

        if plural.hasSuffix("ies"), plural.count > 4 {
            candidates.append(String(plural.dropLast(3)) + "y")
        }

        if plural.hasSuffix("ches") || plural.hasSuffix("shes") || plural.hasSuffix("xes") || plural.hasSuffix("zes") || plural.hasSuffix("ses") {
            candidates.append(String(plural.dropLast(2)))
        }

        if plural.hasSuffix("s"), plural.count > 4 {
            candidates.append(String(plural.dropLast()))
        }

        return Array(Set(candidates)).sorted()
    }

    func lookup(_ token: String) -> CorrectionDictionaryEntry? {
        lookup(token, currentLayout: nil)
    }

    func count(for language: CorrectionDictionaryLanguage) -> Int {
        let customCount = customEntriesByLookupKey.values.filter { $0.language == language }.count
        switch language {
        case .english:
            return englishWords.count + customCount
        case .russian:
            return russianWords.count + customCount
        case .ukrainian:
            return ukrainianWords.count + customCount
        }
    }

    func contains(_ token: String, in layout: KeyboardLayout) -> Bool {
        let word = token.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch layout {
        case .usEnglish: return englishWords.contains(word)
        case .russian: return russianWords.contains(word) || russianInflections.contains(word)
        case .ukrainian: return ukrainianWords.contains(word)
        }
    }

    func dominantRussianUkrainianLayout(for token: String) -> KeyboardLayout? {
        let word = token.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let russian = russianLanguageMarkers.contains(word) && ukrainianWords.contains(word) == false
        let ukrainian = ukrainianLanguageMarkers.contains(word) && contains(word, in: .russian) == false
        guard russian != ukrainian else { return nil }
        return russian ? .russian : .ukrainian
    }

    func frequencyDominantRussianUkrainianLayout(for token: String) -> KeyboardLayout? {
        let word = token.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let russian = russianLanguageMarkers.contains(word)
        let ukrainian = ukrainianLanguageMarkers.contains(word)
        guard russian != ukrainian else { return nil }
        return russian ? .russian : .ukrainian
    }

    private func entryWithCorrectedCapitalization(
        _ entry: CorrectionDictionaryEntry,
        originalToken: String
    ) -> CorrectionDictionaryEntry {
        CorrectionDictionaryEntry(
            wrongToken: entry.wrongToken,
            correctToken: correctedCapitalization(for: originalToken, replacement: entry.correctToken),
            targetLayout: entry.targetLayout,
            sourceLayout: entry.sourceLayout,
            layoutPair: entry.layoutPair,
            language: entry.language,
            source: entry.source
        )
    }

    private func correctedCapitalization(for token: String, replacement: String) -> String {
        let letters = token.unicodeScalars.filter { CharacterSet.letters.contains($0) }
        if letters.isEmpty == false,
           letters.allSatisfy({ CharacterSet.uppercaseLetters.contains($0) }) {
            return replacement.uppercased()
        }

        guard let firstScalar = token.unicodeScalars.first,
              CharacterSet.uppercaseLetters.contains(firstScalar),
              let firstReplacement = replacement.first
        else {
            return replacement
        }

        return firstReplacement.uppercased() + replacement.dropFirst()
    }

    private func lookupScope(for currentLayout: KeyboardLayout?) -> [(layoutPair: CorrectionDictionaryLayoutPair, sourceLayout: KeyboardLayout)]? {
        switch currentLayout {
        case .usEnglish:
            return [(.usRussian, .usEnglish)]
        case .russian:
            return [(.usRussian, .russian)]
        case .ukrainian:
            return []
        case .none:
            return [
                (.usRussian, .usEnglish),
                (.usRussian, .russian)
            ]
        }
    }

    private static func loadBuiltInWordSets() -> (
        russian: SortedWordList,
        russianInflections: RussianInflectionDictionary,
        english: SortedWordList,
        ukrainian: SortedWordList,
        russianMarkers: SortedWordList,
        ukrainianMarkers: SortedWordList,
        trustedRussian: Set<String>,
        trustedEnglish: Set<String>
    ) {
        let russianWords = [
            "привет", "хай", "здравствуй", "спасибо", "пожалуйста", "извини", "простите", "да", "нет", "может", "точно",
            "как", "что", "это", "этот", "эта", "эти", "так", "такой", "такая", "такие",
            "сегодня", "завтра", "вчера", "сейчас", "потом", "раньше", "позже", "скоро", "сразу", "недавно",
            "можно", "нужно", "надо", "нельзя", "хорошо", "плохо", "нормально", "отлично", "готово", "сделано",
            "почему", "зачем", "когда", "куда", "откуда", "где", "кто", "кого", "кому", "чей",
            "какой", "какая", "какое", "какие", "сколько", "насколько", "пока", "всегда", "иногда", "часто",
            "я", "ты", "он", "она", "мы", "вы", "они", "мой", "моя", "мое", "по",
            "мои", "наш", "наша", "наше", "ваш", "ваша", "ваше", "мне", "тебе", "нам",
            "вам", "его", "ее", "их", "себя", "сам", "сама", "сами", "все", "всё",
            "вот", "тут", "там", "здесь", "сюда", "туда", "уже", "еще", "тоже", "только",
            "очень", "почти", "совсем", "просто", "сложно", "быстро", "медленно", "важно", "срочно", "точно",
            "будет", "буду", "будем", "будешь", "будут", "был", "была", "были", "есть", "если",
            "или", "и", "а", "но", "в", "во", "на", "за", "к", "ко", "с", "со", "у", "о",
            "об", "обо", "от", "до", "из", "по", "под", "над", "про", "при",
            "без", "для", "после", "перед", "через", "между", "около",
            "работа", "задача", "проект", "вопрос", "ответ", "команда", "клиент", "письмо", "почта", "встреча",
            "звонок", "созвон", "чат", "сообщение", "файл", "папка", "ссылка", "документ", "таблица", "презентация",
            "комментарий", "заметка", "текст", "слово", "строка", "абзац", "страница", "форма", "поле", "окно",
            "код", "ошибка", "баг", "фикс", "релиз", "сборка", "тесты", "проверка", "готово", "сделано",
            "лог", "логи", "ветка", "коммит", "пуш", "пулл", "мердж", "репозиторий", "сервер", "клиент",
            "открыть", "закрыть", "запустить", "остановить", "перезапустить", "проверить", "исправить", "обновить", "сохранить", "удалить",
            "создать", "найти", "показать", "скрыть", "отправить", "получить", "написать", "читать", "смотреть", "понять",
            "объяснить", "добавить", "убрать", "заменить", "перенести", "выбрать", "отменить", "повторить", "включить", "выключить",
            "думаю", "знаю", "вижу", "могу", "можем", "хочу", "хотим", "давай", "давайте", "окей",
            "ладно", "супер", "понял", "поняла", "понятно", "согласен", "согласна", "помню", "забыл", "забыла",
            "утро", "день", "вечер", "ночь", "время", "час", "минута", "неделя", "месяц", "год",
            "дом", "офис", "город", "страна", "адрес", "улица", "дверь", "комната", "место", "план",
            "деньги", "счет", "цена", "оплата", "заказ", "статус", "сумма", "карта", "банк", "договор",
            "сайт", "страница", "браузер", "поиск", "запрос", "результат", "кнопка", "меню", "настройки", "разрешения",
            "доступ", "мониторинг", "безопасность", "пароль", "логин", "аккаунт", "профиль", "пользователь", "админ", "роль",
            "приложение", "утилита", "система", "сервис", "инструмент", "функция", "режим", "параметр", "опция", "значение",
            "язык", "раскладка", "клавиатура", "ввод", "символ", "пробел", "точка", "запятая", "курсор", "выделение",
            "звук", "уведомление", "диагностика", "трей", "иконка", "окно", "панель", "список", "словарь", "слова",
            "русский", "английский", "переключить", "переключение", "исправление", "автоматически", "вручную", "текущий", "следующий", "последний",
            "первый", "второй", "новый", "старый", "главный", "общий", "личный", "внутренний", "внешний", "локальный",
            "правильно", "неправильно", "случайно", "обычно", "реально", "полностью", "частично", "отдельно", "вместе", "снова",
            "проблема", "решение", "причина", "вариант", "уровень", "риск", "проверка", "результат", "контекст", "поведение",
            "работает", "работают", "работало", "работать", "делает", "делаю", "делаем", "сделай", "сделаем", "сделал",
            "меняется", "поменялось", "открывается", "запускается", "показывается", "добавляется", "удаляется", "исправляется", "переключается", "сохраняется",
            "помогает", "мешает", "ломает", "падает", "висит", "ждет", "ищет", "находит", "читает", "пишет",
            "собрать", "собери", "запусти", "запущено", "останови", "проверь", "посмотри", "открой", "закрой", "перезапусти",
            "расширить", "сократить", "оптимизировать", "улучшить", "упростить", "починить", "дописать", "переписать", "сравнить", "выяснить",
            "например", "потому", "поэтому", "значит", "кстати", "вообще", "именно", "везде", "нигде", "здесь",
            "внутри", "снаружи", "рядом", "ниже", "выше", "слева", "справа", "назад", "вперед", "далее"
        ]
        let russianSupplement = [
            "абсолютно", "аккуратно", "активировать", "активный", "анализ", "аналогично", "архив", "архитектура", "база", "баланс",
            "бывает", "верно", "вернуть", "версия", "вес", "вещь", "вещи", "видно", "видишь", "вкладка",
            "включен", "включена", "включено", "внимание", "возьми", "возьмем", "возможно", "возможность", "войти", "вопросы",
            "восстановить", "вроде", "выглядит", "выдает", "вылезает", "вылетает", "выше", "глобально", "готов", "готова",
            "график", "группа", "данные", "дело", "деплой", "держать", "детали", "дизайн", "длинный", "добавил",
            "добавила", "добавили", "добавим", "добавь", "должен", "должна", "должно", "должны", "долго", "доступен",
            "доступна", "доступно", "другой", "другая", "другое", "другие", "думаешь", "единственный", "если", "живет",
            "зависит", "загрузка", "загрузить", "заголовок", "задание", "зайти", "закрывается", "записать", "запись", "запросить",
            "заработало", "заработает", "зарегистрировать", "зачем", "заходит", "значит", "значение", "изменить", "изменения", "импорт",
            "иногда", "интерфейс", "информация", "использовать", "используется", "исправил", "исправили", "исправим", "итог", "карточка",
            "каталог", "клавиша", "класс", "клик", "кнопки", "команды", "компонент", "конец", "конкретно", "консоль",
            "контрол", "контроль", "конфиг", "копировать", "короткий", "красиво", "критично", "куча", "левая", "левый",
            "легко", "лучше", "любое", "любые", "маленький", "матрица", "меньше", "местами", "миграция", "много",
            "модель", "модуль", "название", "написал", "написали", "направление", "насчет", "начало", "начать", "нашел",
            "нашли", "невозможно", "недостаточно", "некоторые", "немного", "непонятно", "неправильный", "несколько", "нету", "новая",
            "новое", "новые", "нужен", "нужна", "нужны", "обновил", "обновили", "обновим", "обратно", "общее",
            "общий", "объект", "обычный", "обязательно", "один", "одна", "одно", "ожидаемо", "окно", "операция",
            "опции", "основной", "оставить", "осталось", "остальные", "отдельный", "ответил", "отключить", "открыл", "открыли",
            "открытие", "отличается", "отмена", "отчет", "очистить", "ошибки", "падает", "пакет", "пара", "пары",
            "перевести", "передать", "перейти", "переменная", "переместить", "переписка", "перепроверить", "перестало", "переход", "плагин",
            "план", "платформа", "плохой", "поле", "получается", "получилось", "получится", "поменять", "поможет", "попробовать",
            "порядок", "посмотреть", "поставить", "похож", "похоже", "появляется", "правка", "правки", "правый", "предыдущий",
            "предложение", "предупреждение", "пример", "примерно", "проблемы", "провал", "проводить", "прогнать", "программа", "продолжить",
            "продукт", "производство", "пропадает", "протестировать", "процесс", "прошлый", "прямо", "пункт", "пункты", "пустой",
            "пытается", "развернуть", "раздел", "разобраться", "разработка", "разрешение", "разрешить", "раньше", "редактор", "режимы",
            "резко", "релизный", "решить", "решили", "роль", "ручной", "сборку", "сверить", "свойство", "связь",
            "сгенерировать", "сгенерируй", "сделка", "сейчас", "секция", "сильно", "синхронизация", "система", "ситуация", "скрин", "скриншот",
            "следить", "следующий", "сломалось", "словарей", "словарь", "сложно", "сначала", "снизу", "собрал", "собрали",
            "событие", "содержит", "соответственно", "состояние", "способ", "справа", "спросить", "сравнение", "сработало", "сработает",
            "ссылка", "стабильно", "ставить", "стандартный", "старая", "старое", "старт", "стек", "стиль", "строки",
            "структура", "сценарий", "считать", "счетчик", "таб", "текста", "тексты", "терминал", "тип", "токен",
            "токены", "требуется", "триггер", "убирается", "убрал", "убрали", "увеличить", "удалил", "удалили", "удобно",
            "узнать", "улучшение", "уменьшить", "упало", "управление", "уровень", "условие", "установить", "утилиты", "учесть",
            "файлы", "фича", "фокус", "форма", "формат", "фронт", "хватает", "хвост", "хотел",
            "цвет", "целый", "часть", "чистый", "чтобы", "экран", "экспорт", "элемент", "этап", "явно",
            "безопасно", "блокировать", "блокируется", "быстрее", "ввести", "включается", "внешне", "выбрал", "выбрали", "выбор",
            "вывести", "вывод", "выключен", "выключена", "выключено", "выполнить", "генерация", "гипотеза", "глубже", "граница",
            "группы", "дальше", "движение", "действие", "действительно", "добавляется", "документация", "доступы", "ждать", "желательно",
            "зависимость", "замена", "заметил", "запуск", "запущена", "зафиксировать", "защита", "звучит", "изменился", "изменится",
            "использовал", "исключение", "кандидат", "каретка", "контейнер", "коррекция", "крайний", "логика", "локально", "максимум",
            "минимум", "мониторить", "нажать", "найден", "найдется", "настройка", "начинает", "обработать", "обход", "ограничение",
            "описание", "определить", "опыт", "оставил", "отдельно", "отказ", "отказываться", "отладка", "отображение", "очередь",
            "перевод", "переименовать", "переключает", "переключил", "пишу", "пишешь", "повторно", "поддержка", "подключить", "подробно",
            "позволяет", "получаю", "помимо", "попадает", "поправить", "последний", "постоянно", "появилось", "предпочтительно", "приложения",
            "принцип", "проверяет", "проверил", "проверили", "просто", "профиль", "разница", "расширение", "реакция", "реальный",
            "регрессия", "редко", "результаты", "рискованный", "сбрасывается", "сделано", "сильно", "синтетический", "скрыть", "следующее",
            "случай", "случаи", "сначала", "собираю", "совпадает", "создание", "сообщения", "списка", "списки", "статусы",
            "стоит", "схема", "текущий", "тестировать", "точка", "трудно", "уведомить", "увидеть", "удобнее", "указать",
            "улучшить", "успешно", "устойчиво", "уточнить", "фактически", "финальный", "фокусировка", "формы", "хороший", "хранить"
        ]
        let generatedRussianWords = resourceWords(named: "russian")
        let trustedRussianWordSet = Set(russianWords + russianSupplement)
        let russianWordList = SortedWordList(
            words: generatedRussianWords,
            adding: trustedRussianWordSet
        )

        let englishWords = [
            "i", "i'm", "hello", "hey", "okay", "okey", "->", "us", "so", "thanks", "thank", "please", "yes", "no", "how", "what", "what's", "this", "that", "that's",
            "today", "tomorrow", "yesterday", "now", "later", "soon", "can", "need", "good", "bad", "on",
            "why", "where", "when", "who", "which", "work", "works", "make", "add", "remove",
            "open", "close", "start", "stop", "restart", "check", "fix", "update", "save", "delete",
            "create", "find", "show", "hide", "send", "receive", "write", "read", "watch", "explain",
            "settings", "meeting", "call", "email", "project", "task", "question", "answer", "team", "client",
            "message", "file", "link", "document", "table", "comment", "code", "error", "bug", "release",
            "build", "test", "tests", "ready", "done", "server", "browser", "search", "query", "result",
            "api", "button", "menu", "window", "app", "tool", "feature", "mode", "option", "value", "language",
            "keyboard", "input", "space", "cursor", "selection", "sound", "notification", "diagnostics", "status", "default"
        ]
        let englishSupplement = [
            "about", "above", "access", "account", "action", "active", "actual", "adapter", "admin", "again",
            "agent", "allow", "allowed", "always", "amount", "answer", "apply", "archive", "area", "argument",
            "around", "array", "asset", "async", "attempt", "available", "avoid", "background", "backup", "base",
            "before", "behavior", "below", "block", "blocked", "branch", "bundle", "cache", "callback", "candidate",
            "cannot", "capture", "case", "change", "changes", "channel", "check", "checked", "clean", "clear",
            "client", "clipboard", "close", "closed", "command", "comment", "common", "compact", "compile", "complete",
            "component", "condition", "config", "confirm", "connection", "console", "constant", "context", "control", "copy",
            "correct", "correction", "count", "create", "crypto", "current", "data", "debug", "decision", "default", "delete",
            "delimiter", "dependency", "deploy", "description", "desktop", "detail", "detect", "diagnostic", "dictionary", "disable",
            "disabled", "display", "document", "done", "download", "duplicate", "edit", "element", "enabled", "engine",
            "entry", "error", "event", "exact", "example", "exception", "expected", "fallback", "false", "field",
            "final", "first", "focus", "focused", "folder", "format", "found", "future", "generate", "global",
            "guard", "handle", "hidden", "history", "ignore", "image", "import", "include", "index", "input",
            "insert", "internal", "issue", "keyboard", "language", "last", "launch", "layout", "level", "line",
            "list", "local", "logic", "logo", "manual", "mapping", "materials", "matrix", "message", "metadata", "method", "missing",
            "model", "module", "monitor", "name", "native", "network", "never", "next", "node", "normal",
            "object", "observe", "open", "option", "output", "override", "package", "panel", "password", "patch",
            "permission", "policy", "position", "possible", "prepare", "present", "preview", "primary", "process", "product",
            "project", "prompt", "property", "quick", "range", "ready", "reason", "record", "refresh", "release",
            "reload", "remove", "replace", "replacement", "request", "required", "reset", "resolve", "resource", "response",
            "result", "rewrite", "risk", "role", "root", "route", "safe", "safety", "save", "screen",
            "script", "search", "section", "secure", "selected", "selection", "send", "server", "service", "setting",
            "settings", "shell", "short", "shortcut", "show", "simple", "source", "stable", "start", "state",
            "status", "stop", "store", "string", "structure", "summary", "support", "supported", "switch", "system",
            "target", "terminal", "test", "tests", "text", "thread", "thumbnail", "toggle", "token", "trace", "tree",
            "trigger", "true", "type", "unknown", "update", "upload", "user", "value", "verify", "version",
            "view", "visible", "warning", "where", "window", "word", "words", "workflow", "write", "wrong"
        ]
        let generatedEnglishWords = resourceWords(named: "english")
        let trustedEnglishWordSet = Set(englishWords + englishSupplement)
        let englishWordList = SortedWordList(
            words: generatedEnglishWords,
            adding: trustedEnglishWordSet
        )
        let ukrainianGeneratedNoise: Set<String> = [
            "щт", "туц", "філ", "філі", "уес", "рщт", "ьуп", "рьщ", "зоі"
        ]
        let ukrainianWordList = SortedWordList(
            words: resourceWords(named: "ukrainian").filter {
                ukrainianGeneratedNoise.contains($0) == false
            }
        )
        let russianMarkers = SortedWordList(words: resourceWords(named: "russian-markers"))
        let ukrainianMarkers = SortedWordList(words: resourceWords(named: "ukrainian-markers"))

        return (
            russian: russianWordList,
            russianInflections: RussianInflectionDictionary(
                baseLines: resourceWords(named: "russian-inflection-bases"),
                ruleLines: resourceWords(named: "russian-inflection-rules")
            ),
            english: englishWordList,
            ukrainian: ukrainianWordList,
            russianMarkers: russianMarkers,
            ukrainianMarkers: ukrainianMarkers,
            trustedRussian: trustedRussianWordSet,
            trustedEnglish: trustedEnglishWordSet
        )
    }

    private static func resourceWords(named name: String) -> [String] {
        let appResourceBundleURL = Bundle.main.resourceURL?.appendingPathComponent("TypeSwitch_TypeSwitchApp.bundle")
        let appResourceBundle = appResourceBundleURL.flatMap(Bundle.init(url:))
        let url = appResourceBundle?.url(forResource: name, withExtension: "txt")
            ?? Bundle.module.url(forResource: name, withExtension: "txt", subdirectory: "FrequencyWords")
            ?? Bundle.module.url(forResource: name, withExtension: "txt")
        guard let url, let content = try? String(contentsOf: url, encoding: .utf8) else {
            return []
        }

        return content
            .split(whereSeparator: \.isNewline)
            .compactMap { line in
                let word = line.trimmingCharacters(in: .whitespacesAndNewlines)
                guard word.isEmpty == false, word.hasPrefix("#") == false else {
                    return nil
                }
                return word
            }
    }

    private struct LookupKey: Hashable {
        let layoutPair: CorrectionDictionaryLayoutPair
        let sourceLayout: KeyboardLayout
        let wrongToken: String

        init(layoutPair: CorrectionDictionaryLayoutPair, sourceLayout: KeyboardLayout, wrongToken: String) {
            self.layoutPair = layoutPair
            self.sourceLayout = sourceLayout
            self.wrongToken = wrongToken.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        }
    }

    private struct SortedWordList {
        private let words: [String]

        init(words: [String], adding additionalWords: Set<String> = []) {
            if additionalWords.isEmpty {
                self.words = words
            } else {
                self.words = Array(Set(words).union(additionalWords)).sorted()
            }
        }

        var count: Int {
            words.count
        }

        func contains(_ word: String) -> Bool {
            var lowerBound = 0
            var upperBound = words.count

            while lowerBound < upperBound {
                let middle = lowerBound + (upperBound - lowerBound) / 2
                if words[middle] < word {
                    lowerBound = middle + 1
                } else {
                    upperBound = middle
                }
            }

            return lowerBound < words.count && words[lowerBound] == word
        }
    }
}
