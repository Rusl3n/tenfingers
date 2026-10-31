// Тексты шагов урока издания 2 (спецификация фазы 6, §2.2, §2.5, §6.1–§6.2; §16, решения 5, 8, 9, 23).

/// Урок издания 2, готовый к генерации: шаги, фокус, слабые и сильные буквы, пулы слов, отобранные предложения
/// корпуса и библиотеки. Всё это считается один раз (`LessonPlanner.prepare`); `exercises(rng:)` только собирает тексты.
public struct PreparedLesson: Sendable {
    public let context: LessonContext
    public let steps: [ResolvedStep]
    /// Фокус урока: новые клавиши ∪ односимвольные `focus` (строчные); у `rows` — буквы рядов урока.
    public let lessonFocus: Set<Character>
    /// Многосимвольные `focus` урока («ъе», «вств», «th»).
    public let lessonBigrams: [String]
    /// «Повтор»: 5 букв и 5 сочетаний с наибольшей долей ошибок, без данных — решение 23.
    public let weakKeys: [Character]
    public let weakBigrams: [String]
    /// «Ускорение»: сильные буквы (`WeakSpots.strongKeys`).
    public let strongKeys: [Character]

    /// Если подходящих предложений корпуса меньше, шаг `sentences` строит генератор (§2.5).
    static let minimumCorpusSentences = 20
    /// Доля сильных букв в словах «Ускорения» (§6.2).
    static let strongShare = 0.8
    /// «Частые слова» в предложениях: все слова — из стольких первых слов словаря.
    static let frequentDictionaryWords = 3000
    /// «Длинные слова» в предложениях: не меньше `longWordsPerSentence` слов от `longWordLength` букв.
    static let longWordLength = 7
    static let longWordsPerSentence = 2
    /// «Повтор» без данных — меньше стольких букв с объёмом (§6.1); берутся последние `fallbackKeys` новых букв.
    /// С данными слабых букв не меньше `minimumKeysWithData`: недостающие — из тех же последних новых букв.
    static let minimumKeysWithData = 3
    static let fallbackKeys = 5
    /// Последнее предложение шага `sentences` (и `sprint` из предложений) не уводит текст дальше этой доли длины,
    /// если есть предложение, которое укладывается.
    static let maxSentencesOvershoot = 1.25

    private let generator: TextGenerator
    private let sentenceGenerator: SentenceGenerator
    /// Строчные буквы, открытые к уроку.
    private let allowedLetters: Set<Character>
    /// Пул слов урока (`lesson.wordPool`, по умолчанию `all`), пул фраз (`frequent`) и пул `focus`/`errorWords`
    /// (`TextGenerator.focusPool`; пусто, если таких шагов нет).
    private let wordPool: [String]
    private let phrasePool: [String]
    private let focusPool: [String]
    private let capitalRate: Double
    private let style: TextStyle
    /// До 5 открытых букв с наибольшей долей ошибок (шаги `focus` обычных уроков).
    private let errorKeys: [Character]
    /// Предложения корпуса в стиле этапа: сначала с фокусными символами урока, затем остальные.
    private let focusedCorpus: [String]
    private let otherCorpus: [String]
    /// Предложения отрывков библиотеки (`textSource`) в стиле этапа: по отрывку, по порядку; пустые отрывки убраны.
    private let libraryExcerpts: [[String]]
    /// Таблицы кандидатов (от семени не зависят, тест каталога строит 20 планов): слова пула фокуса с каждой целью
    /// шагов `focus` и `errorWords`, слова пула урока и пула фраз с каждой фокусной буквой, отбор `rowWords` по шагам
    /// (`nil` — не `rowWords`) и слова «Ускорения». Порядок слов — как у пулов, фильтры — как в генераторах.
    private let focusWordsByTarget: [String: [String]]
    private let errorWordsByTarget: [Character: [String]]
    private let wordsByLetter: [Character: [String]]
    private let phrasesByLetter: [Character: [String]]
    private let rowSelections: [TextGenerator.RowWordsSelection?]
    private let strongSelection: TextGenerator.RowWordsSelection?

    init(context ctx: LessonContext, learner: LearnerStats, generator: TextGenerator, corpus: [CorpusSentence],
         library: [LibraryText]) {
        context = ctx
        steps = StepTemplates.resolve(ctx)
        self.generator = generator
        sentenceGenerator = SentenceGenerator(generator: generator)
        let lesson = ctx.lesson
        allowedLetters = ctx.allowed.filter { $0.isLetter && !$0.isUppercase }

        // Фокус урока.
        let singleFocus = (lesson.focus ?? []).filter { $0.count == 1 }.compactMap { $0.lowercased().first }
        if lesson.resolvedKind == .rows {
            lessonFocus = (lesson.rows ?? []).reduce(into: Set<Character>()) { $0.formUnion(ctx.rows[$1] ?? []) }
        } else {
            lessonFocus = Set(lesson.newCharacters).union(singleFocus)
        }
        lessonBigrams = (lesson.focus ?? []).filter { $0.count > 1 }

        // «Повтор» (§6.1, решение 23) и «Ускорение» (§6.2).
        let mostErrors = WeakSpots.mostErrors(keys: learner.keys, bigrams: learner.bigrams, allowed: allowedLetters,
                                                 boosted: learner.hardLetters)
        let keysWithData = allowedLetters.filter { (learner.keys[$0]?.presses ?? 0) >= WeakSpots.minimumKeyPresses }
        let stageLetters = ctx.stageNewKeys.filter { $0.isLetter }
        let fallback = Array((stageLetters.isEmpty ? ctx.introducedKeys.filter { $0.isLetter } : stageLetters)
            .suffix(Self.fallbackKeys))
        if keysWithData.count < Self.minimumKeysWithData {
            weakKeys = fallback
        } else {
            // Слабых меньше трёх — добираем последними новыми буквами (с самой новой).
            var keys = mostErrors.keys
            for letter in fallback.reversed() where keys.count < Self.minimumKeysWithData && !keys.contains(letter) {
                keys.append(letter)
            }
            weakKeys = keys
        }
        weakBigrams = mostErrors.bigrams
        errorKeys = mostErrors.keys
        strongKeys = WeakSpots.strongKeys(learner.keys, allowed: ctx.allowed)

        capitalRate = lesson.capitals == true ? 0.5 : (ctx.capitals ? 0.15 : 0)
        style = ctx.stage.textStyle ?? .lowerPlain
        wordPool = generator.pool(letters: allowedLetters, kind: lesson.wordPool ?? .all)
        phrasePool = generator.pool(letters: allowedLetters, kind: .frequent)
        focusPool = steps.contains { $0.kind == .focus || $0.kind == .errorWords }
            ? generator.focusPool(letters: allowedLetters) : []

        // Таблицы кандидатов: те же цели, что выбирают `focusedWords`, `words`, `phrases` и `rowWords` ниже.
        let focusPool = self.focusPool, wordPool = self.wordPool, phrasePool = self.phrasePool
        if focusPool.isEmpty {
            focusWordsByTarget = [:]
        } else {
            let keys = Set(lessonFocus).union(weakKeys).union(errorKeys)
            let targets = keys.map { String($0) } + lessonBigrams + weakBigrams
            focusWordsByTarget = Dictionary(
                targets.map { target in (target, focusPool.filter { $0.contains(target) }) },
                uniquingKeysWith: { first, _ in first })
        }
        errorWordsByTarget = steps.contains { $0.kind == .errorWords }
            ? Dictionary(Set(weakKeys).map { key in (key, focusPool.filter { $0.contains(key) }) },
                         uniquingKeysWith: { first, _ in first })
            : [:]
        let lessonFocus = self.lessonFocus, weakKeys = self.weakKeys, strongKeys = self.strongKeys
        let wordFocus = steps.reduce(into: Set<Character>()) { letters, step in
            letters.formUnion(Self.stepFocus(step.focus, kind: lesson.resolvedKind, weakKeys: weakKeys,
                                             strongKeys: strongKeys, lessonFocus: lessonFocus).filter(\.isLetter))
        }
        wordsByLetter = Dictionary(uniqueKeysWithValues: wordFocus.map { letter in
            (letter, wordPool.filter { $0.contains(letter) })
        })
        phrasesByLetter = Dictionary(uniqueKeysWithValues: lessonFocus.filter(allowedLetters.contains).map { letter in
            (letter, phrasePool.filter { $0.contains(letter) })
        })
        rowSelections = steps.map { step in
            guard step.kind == .rowWords else { return nil }
            return Self.rowSelection(step, context: ctx, generator: generator, pool: wordPool)
        }
        // «Ускорение» (§6.2): слова, где не меньше 80% букв сильные; `nil` — открытых строчных букв нет.
        let strong = Set(strongKeys)
        let strongPool = wordPool.filter {
            Double($0.filter(strong.contains).count) >= Self.strongShare * Double($0.count) - 1e-9
        }
        strongSelection = generator.rowWordsSelection(rowLetters: strong, allowed: ctx.allowed,
                                                      minShare: Self.strongShare, pool: strongPool)

        // Корпус: стиль этапа, пул слов урока, сначала предложения с фокусными символами (§2.5). Без длины `text`
        // у этапа шагов из предложений нет (решение 5): корпус и библиотека не нормализуются зря.
        let style = self.style
        let hasText = (ctx.stage.lengths ?? StepLengths()).hasText
        let corpus = hasText ? corpus : []
        let library = hasText ? library : []
        let styledCorpus = corpus.compactMap {
            TextNormalizer.styled($0.text, style: style, allowed: ctx.allowed, capitals: ctx.capitals)
        }
        let fitting: [String]
        switch lesson.wordPool {
        case .frequent:
            let frequent = Set(generator.wordList.words.prefix(Self.frequentDictionaryWords))
            fitting = styledCorpus.filter { Self.sentenceWords($0).allSatisfy(frequent.contains) }
        case .long:
            fitting = styledCorpus.filter {
                Self.sentenceWords($0).filter { $0.count >= Self.longWordLength }.count >= Self.longWordsPerSentence
            }
        case .all, nil:
            fitting = styledCorpus
        }
        let sentenceFocus = Self.lessonLevelFocus(ctx.lesson.resolvedKind, weakKeys: weakKeys, strongKeys: strongKeys,
                                                  lessonFocus: lessonFocus)
        let bigrams = lessonBigrams
        func isFocused(_ sentence: String) -> Bool {
            sentence.lowercased().contains(where: sentenceFocus.contains) || bigrams.contains { sentence.contains($0) }
        }
        focusedCorpus = fitting.filter(isFocused)
        otherCorpus = fitting.filter { !isFocused($0) }

        // Библиотека: отрывки `textSource` (или все), их предложения в стиле этапа.
        let excerpts = lesson.textSource.map { source in library.filter { $0.id.hasPrefix(source) } } ?? library
        libraryExcerpts = excerpts.map { excerpt in
            TextNormalizer.sentences(excerpt.text).compactMap {
                TextNormalizer.styled($0, style: style, allowed: ctx.allowed, capitals: ctx.capitals)
            }
        }.filter { !$0.isEmpty }
    }

    /// Тексты шагов по порядку; `id` — номер шага в плане. Связный текст разных шагов берётся из разных отрывков
    /// библиотеки, пока неиспользованные отрывки есть (`usedExcerpts`).
    public func exercises<G: RandomNumberGenerator>(rng: inout G) -> [ExerciseSpec] {
        var usedExcerpts = Set<Int>()
        return steps.enumerated().map { index, step in
            let (text, connected) = text(for: step, at: index, usedExcerpts: &usedExcerpts, rng: &rng)
            return ExerciseSpec(id: index, kind: step.kind, title: step.title, text: text, connected: connected)
        }
    }

    /// Один шаг вида `kind` длиной `length` вне плана урока — «Текст» плана дня (§10.1, решение 12 фазы 6c):
    /// `text` в стиле этапа урока или `phrases`. Фокус — урока; `rowWords` (нужен отбор рядов шага) — слова урока.
    public func exercise<G: RandomNumberGenerator>(_ kind: ExerciseKind, length: Int, rng: inout G) -> ExerciseSpec {
        let kind = kind == .rowWords ? .words : kind
        let step = ResolvedStep(kind: kind, length: length, rows: [], minShare: nil, focus: nil, title: kind.titleKey)
        var usedExcerpts = Set<Int>()
        let (text, connected) = text(for: step, at: 0, usedExcerpts: &usedExcerpts, rng: &rng)
        return ExerciseSpec(id: 0, kind: kind, title: step.title, text: text, connected: connected)
    }

    // MARK: - Тексты шагов

    private var kind: LessonKind { context.lesson.resolvedKind }

    /// Фокус шага: слабые буквы (`weakLetters`), сильные (`strong`), иначе фокус урока
    /// (у «Повтора» — слабые буквы, у «Ускорения» — сильные).
    private func focusSet(_ step: ResolvedStep) -> Set<Character> {
        Self.stepFocus(step.focus, kind: kind, weakKeys: weakKeys, strongKeys: strongKeys, lessonFocus: lessonFocus)
    }

    private static func stepFocus(_ focus: StepFocus?, kind: LessonKind, weakKeys: [Character],
                                  strongKeys: [Character], lessonFocus: Set<Character>) -> Set<Character> {
        switch focus {
        case .weakLetters: Set(weakKeys)
        case .strong: Set(strongKeys)
        case .weakBigrams, nil:
            lessonLevelFocus(kind, weakKeys: weakKeys, strongKeys: strongKeys, lessonFocus: lessonFocus)
        }
    }

    /// Отбор слов шага `rowWords`: ряды шага ∩ открытые буквы, пары — первый ряд и остальные.
    private static func rowSelection(_ step: ResolvedStep, context: LessonContext, generator: TextGenerator,
                                     pool: [String]) -> TextGenerator.RowWordsSelection? {
        let rowSets = step.rows.map { context.rows[$0] ?? [] }
        let rowLetters = rowSets.reduce(into: Set<Character>()) { $0.formUnion($1) }
        let pairs = rowSets.count >= 2
            ? (rowSets[0], rowSets.dropFirst().reduce(into: Set<Character>()) { $0.formUnion($1) })
            : nil
        return generator.rowWordsSelection(rowLetters: rowLetters, allowed: context.allowed,
                                           minShare: step.minShare ?? StepTemplates.singleRowShare, pairs: pairs,
                                           pool: pool)
    }

    private static func lessonLevelFocus(_ kind: LessonKind, weakKeys: [Character], strongKeys: [Character],
                                         lessonFocus: Set<Character>) -> Set<Character> {
        switch kind {
        case .review: Set(weakKeys)
        case .speedup: Set(strongKeys)
        default: lessonFocus
        }
    }

    /// Текст шага и признак связного текста (`ExerciseSpec.connected`).
    private func text<G: RandomNumberGenerator>(for step: ResolvedStep, at index: Int, usedExcerpts: inout Set<Int>,
                                                rng: inout G) -> (String, Bool) {
        let length = step.length
        let lesson = context.lesson
        let hasText = (context.stage.lengths ?? StepLengths()).hasText
        let text: String
        switch step.kind {
        case .drill:
            if kind == .review {
                text = generator.drill(keys: Array(weakKeys.prefix(3)), length: length, rng: &rng)
            } else if lesson.capitals == true && lesson.newKeys.isEmpty {
                text = generator.capitalWords(initials: lessonFocus, allowed: context.allowed, length: length, rng: &rng)
            } else {
                text = generator.drill(keys: lesson.newCharacters, length: length, rng: &rng)
            }
        case .combos:
            if !lesson.newKeys.isEmpty {
                text = generator.combos(newKeys: lesson.newCharacters, allowed: context.allowed, length: length,
                                        rng: &rng)
            } else if lesson.capitals == true {
                text = generator.capitalWords(initials: lessonFocus, allowed: context.allowed, length: length, rng: &rng)
            } else {
                text = ""
            }
        case .words:
            text = step.focus == .strong
                ? strongWords(length: length, rng: &rng)
                : words(focus: focusSet(step), length: length, rng: &rng)
        case .rowWords:
            let rowSets = step.rows.map { context.rows[$0] ?? [] }
            text = generator.rowWords(rowLetters: rowSets.reduce(into: Set<Character>()) { $0.formUnion($1) },
                                      allowed: context.allowed, minShare: step.minShare ?? StepTemplates.singleRowShare,
                                      length: length, pool: wordPool, selection: rowSelections[index], rng: &rng)
        case .phrases:
            text = phrases(length: length, rng: &rng)
        case .sentences:
            if let text = connected(sentences(focus: focusSet(step), length: length, rng: &rng)) { return text }
            text = ""
        case .text:
            let passage = connectedText(focus: focusSet(step), length: length, usedExcerpts: &usedExcerpts,
                                        rng: &rng)
            if let text = connected(passage) { return text }
            text = ""
        case .focus:
            text = focusedWords(step, length: length, rng: &rng)
        case .errorWords:
            text = generator.errorWords(letters: allowedLetters, targets: weakKeys, length: length, pool: focusPool,
                                        wordsByTarget: errorWordsByTarget, rng: &rng)
        case .sprint:
            if step.focus == .strong {
                text = strongWords(length: length, rng: &rng)
            } else if hasText, let text = connected(sentences(focus: focusSet(step), length: length, rng: &rng)) {
                return text
            } else {
                text = phrases(length: length, rng: &rng)
            }
        case .numbers:
            text = SymbolDrill.text(language: context.language, allowed: context.allowed, generator: generator,
                                    length: length, rng: &rng)
        case .check, .refresh:
            if hasText {
                let passage = connectedText(focus: focusSet(step), length: length, usedExcerpts: &usedExcerpts,
                                            rng: &rng)
                if let text = connected(passage) { return text }
            }
            text = words(focus: focusSet(step), length: length, rng: &rng)
        }
        // Генератору не из чего строить (нет новых клавиш, слов с фокусом, предложений): шаг — слова урока.
        return (text.isEmpty ? words(focus: focusSet(step), length: length, rng: &rng) : text, false)
    }

    /// Связный текст шага; пустой — `nil` (тогда шаг строится словами урока).
    private func connected(_ text: String) -> (String, Bool)? {
        text.isEmpty ? nil : (text, true)
    }

    /// Слова урока. Пунктуация этапа `none` (§2.5): знаки к словам не приставляются, кроме новых знаков урока
    /// (это его цель: «C и запятая», «A и ;»); иначе — все открытые.
    private func words<G: RandomNumberGenerator>(focus: Set<Character>, length: Int, rng: inout G) -> String {
        let decorations = style.punctuation == .none
            ? Set(context.lesson.newCharacters.filter { !$0.isLetter }) : nil
        return generator.words(allowed: context.allowed, focus: focus, length: length, capitalRate: capitalRate,
                               pool: wordPool, extraWords: context.lesson.extraWords ?? [],
                               focusedByLetter: wordsByLetter, decorations: decorations, rng: &rng)
    }

    /// «Ускорение» (§6.2): слова, где не меньше 80% букв сильные. Пул заранее отфильтрован по доле (`strongSelection`
    /// в `init`): `rowWords` снижает порог при нехватке слов, а здесь недостачу восполняют псевдослова из сильных букв.
    /// Без отбора (нет открытых строчных букв) генератор, как и прежде, возвращает пустую строку.
    private func strongWords<G: RandomNumberGenerator>(length: Int, rng: inout G) -> String {
        generator.rowWords(rowLetters: Set(strongKeys), allowed: context.allowed, minShare: Self.strongShare,
                           length: length, selection: strongSelection, rng: &rng)
    }

    private func phrases<G: RandomNumberGenerator>(length: Int, rng: inout G) -> String {
        generator.phrases(allowed: context.allowed, focus: lessonFocus, length: length, pool: phrasePool,
                          focusedByLetter: phrasesByLetter, rng: &rng)
    }

    /// `focus`: сочетания «Повтора» (нет — его буквы); иначе слабые буквы «Повтора» или топ-5 ошибок урока
    /// (меньше 3 — фокус урока) вместе с сочетаниями урока.
    private func focusedWords<G: RandomNumberGenerator>(_ step: ResolvedStep, length: Int, rng: inout G) -> String {
        if step.focus == .weakBigrams {
            return weakBigrams.isEmpty
                ? generator.focusedWords(letters: allowedLetters, focusKeys: weakKeys, focusBigrams: [], length: length,
                                         pool: focusPool, wordsByTarget: focusWordsByTarget, rng: &rng)
                : generator.focusedWords(letters: allowedLetters, focusKeys: [], focusBigrams: weakBigrams,
                                         length: length, pool: focusPool, wordsByTarget: focusWordsByTarget, rng: &rng)
        }
        let keys: [Character]
        if step.focus == .weakLetters || kind == .review {
            keys = weakKeys
        } else {
            keys = errorKeys.count >= Self.minimumKeysWithData ? errorKeys : lessonFocus.sorted()
        }
        return generator.focusedWords(letters: allowedLetters, focusKeys: keys, focusBigrams: lessonBigrams,
                                      length: length, pool: focusPool, wordsByTarget: focusWordsByTarget, rng: &rng)
    }

    /// Предложения корпуса до длины, сначала с фокусными символами; подходящих меньше 20 — генератор (§2.5).
    /// Последним берётся предложение, с которым текст не длиннее `length × 1,25` (если такое есть; иначе — самое
    /// короткое): шаг `sprint` на 100 знаков не должен выйти вдвое длиннее.
    private func sentences<G: RandomNumberGenerator>(focus: Set<Character>, length: Int, rng: inout G) -> String {
        guard focusedCorpus.count + otherCorpus.count >= Self.minimumCorpusSentences else {
            return generated(focus: focus, length: length, rng: &rng)
        }
        let upper = Int(Double(length) * Self.maxSentencesOvershoot)
        var remaining = focusedCorpus.shuffled(using: &rng) + otherCorpus.shuffled(using: &rng)
        var parts: [String] = []
        var total = -1  // без пробела перед первым предложением
        while total < length && !remaining.isEmpty {
            // Предложение либо не дотягивает до длины, либо завершает текст в пределах верхней границы.
            let next = total + 1
            let index = remaining.firstIndex { next + $0.count < length || next + $0.count <= upper }
                ?? remaining.indices.min { remaining[$0].count < remaining[$1].count }!
            let sentence = remaining.remove(at: index)
            parts.append(sentence)
            total += sentence.count + 1
        }
        return parts.joined(separator: " ")
    }

    /// Связный текст (решение 8): предложения одного отрывка подряд. Отрывок случайный из ещё не взятых другими
    /// шагами урока (`usedExcerpts`; все взяты — любой), начало — такое, чтобы остатка отрывка хватило на длину шага;
    /// в следующий отрывок текст переходит, только если отрывок короче шага. Не хватает и всех отрывков — предложения
    /// корпуса, затем генератор; по границе слова до длины (`TextChunker`).
    private func connectedText<G: RandomNumberGenerator>(focus: Set<Character>, length: Int,
                                                         usedExcerpts: inout Set<Int>, rng: inout G) -> String {
        var parts: [String] = []
        var total = -1
        func add(_ sentence: String) {
            parts.append(sentence)
            total += sentence.count + 1
        }
        if !libraryExcerpts.isEmpty {
            let unused = libraryExcerpts.indices.filter { !usedExcerpts.contains($0) }
            let first = unused.isEmpty
                ? Int.random(in: 0..<libraryExcerpts.count, using: &rng)
                : unused.randomElement(using: &rng)!
            usedExcerpts.insert(first)
            let excerpt = libraryExcerpts[first]
            // Длина остатка отрывка с i-го предложения; годные начала — где остатка хватает на шаг.
            var suffix = Array(repeating: -1, count: excerpt.count + 1)
            for index in excerpt.indices.reversed() { suffix[index] = suffix[index + 1] + excerpt[index].count + 1 }
            let starts = excerpt.indices.filter { suffix[$0] >= length }
            let start = starts.isEmpty ? 0 : starts.randomElement(using: &rng)!
            for sentence in excerpt[start...] where total < length { add(sentence) }
            for offset in 1..<libraryExcerpts.count where total < length {
                let next = (first + offset) % libraryExcerpts.count
                usedExcerpts.insert(next)
                for sentence in libraryExcerpts[next] where total < length { add(sentence) }
            }
        }
        if total < length {
            for sentence in focusedCorpus.shuffled(using: &rng) + otherCorpus.shuffled(using: &rng) where total < length {
                add(sentence)
            }
        }
        if total < length {
            add(generated(focus: focus, length: length - max(total, 0), rng: &rng))
        }
        return TextChunker.chunk(parts.joined(separator: " "), from: 0, size: length).text
    }

    private func generated<G: RandomNumberGenerator>(focus: Set<Character>, length: Int, rng: inout G) -> String {
        sentenceGenerator.text(language: context.language, allowed: context.allowed,
                               capitals: context.capitals && style.case == .mixed, digits: style.digits,
                               focus: focus, pool: wordPool, length: length, rng: &rng)
    }

    /// Слова предложения для фильтра пула: строчные, без знаков; однобуквенные и с апострофом не проверяются
    /// (в словаре их нет: «в», «и», «don't»).
    private static func sentenceWords(_ sentence: String) -> [String] {
        sentence.lowercased().split(whereSeparator: { !$0.isLetter && $0 != "'" })
            .filter { $0.count > 1 && !$0.contains("'") }.map(String.init)
    }
}
