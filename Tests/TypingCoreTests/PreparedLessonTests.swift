import Testing
@testable import TypingCore

// Тексты шагов издания 2 (§2.2, §2.5, §6.1–§6.2; решения 5, 8, 23): маленький словарь, корпус и библиотека — в тесте.

private let dictionary = [
    "вол", "вал", "лак", "кол", "век", "лев", "овал", "лава", "кока", "вело", "колео", "екал", "вак", "ока",
    "вола", "вала", "лова", "олово", "алло", "волов", "валов",
    "мама", "мыла", "раму", "дом", "кот", "лес", "река", "вода", "небо", "солнце", "город", "окно", "стол",
    "книга", "ветер", "поле", "дорога", "мальчик", "девочка", "утро", "вечер", "зима", "лето", "осень",
    "весна", "снег", "дождь", "трава", "цветок", "дерево", "птица", "рыба", "море", "гора", "берег", "сад",
    "тихий", "светлый", "тёплый", "ёлка", "ёж", "лёд", "шёл", "идёт", "читает", "пишет", "смотрит", "думает",
    "старый", "новый", "белый", "синий", "большой", "малый", "хороший", "долгий", "быстро", "медленно",
    "день", "ночь", "друг", "брат", "сестра", "отец", "мать", "семья", "школа", "работа", "время", "жизнь",
    "щука", "щи", "чай", "час", "юла", "яблоко", "жук", "эхо", "съел", "подъезд", "гриб", "хлеб", "фонарь",
]
private let generator = TextGenerator(wordList: WordList(words: dictionary))

private let corpusTexts = [
    "Мама мыла раму.", "Кот спит на столе.", "Утром шёл снег.", "Над рекой летит птица.",
    "Дорога идёт через поле.", "В саду растёт старое дерево.", "Брат читает новую книгу.",
    "Сестра пишет письмо другу.", "Зимой у нас много снега.", "Летом мы ходим к морю.",
    "Отец работает в городе.", "Вечером в окне горит свет.", "Ветер гонит облака по небу.",
    "Рыба плывёт у самого берега.", "Девочка смотрит на цветок.", "Мальчик думает о лете.",
    "Тёплый дождь шёл всю ночь.", "Ёлка стоит у самой двери.", "Мы пьём чай с хлебом.",
    "Весной в лесу поют птицы.", "Осенью листья падают с деревьев.", "На горе лежит белый снег.",
    "Солнце встало над морем.", "Семья сидит за большим столом.",
]
private let corpus = corpusTexts.enumerated().map { CorpusSentence(text: $1, traits: 3, source: "tatoeba:\($0)") }

private let pushkin = [
    LibraryText(id: "ru.pushkin.tale", title: "Повесть", author: "Пушкин",
                text: "Метель не утихала. Старый дом стоял на краю села. Ямщик долго ехал по тёмной дороге. "
                    + "Вдали показался огонёк. Мы вошли в избу и сели у печи. Хозяйка поставила на стол самовар. "
                    + "За окном выл ветер, а в избе было тепло и тихо.", source: ""),
    LibraryText(id: "ru.pushkin.tale.2", title: "Повесть · 2", author: "Пушкин",
                text: "Утром буря стихла. Солнце осветило белые поля. Ямщик запряг лошадей, и мы поехали дальше. "
                    + "Дорога шла через лес. Снег блестел на ветвях. К вечеру мы увидели город.", source: ""),
]
private let chekhov = LibraryText(id: "ru.chekhov.dog", title: "Каштанка", author: "Чехов",
                                  text: "Каштанка бегала по улице. Хозяин потерялся в толпе. Каштанка искала его до "
                                      + "ночи. Незнакомец позвал собаку к себе.", source: "")

private func prepare(_ lessonId: String, in course: Course? = nil, learner: LearnerStats = .empty,
                     corpus: [CorpusSentence] = corpus, library: [LibraryText] = pushkin + [chekhov])
    throws -> PreparedLesson {
    let course = try course ?? CourseFixtures.ruMini()
    let planner = LessonPlanner(generator: generator, corpus: corpus, library: library)
    return planner.prepare(try #require(course.context(for: lessonId)), learner: learner)
}

private func mastery(_ errorRate: Double, presses: Int = 40) -> KeyMastery {
    KeyMastery(ewmaMs: 200, errorRate: errorRate, presses: presses)
}

@Test(arguments: ["mini", "text"])
func everyFixtureStepUsesOpenCharactersAndHasItsLength(fixture: String) throws {
    let course = try fixture == "mini" ? CourseFixtures.ruMini() : CourseFixtures.ruText()
    let hasText = { (ctx: LessonContext) in (ctx.stage.lengths ?? StepLengths()).hasText }
    for lesson in course.lessons {
        let ctx = try #require(course.context(for: lesson.id))
        let prepared = try prepare(lesson.id, in: course)
        for seed in UInt64(1)...20 {
            var rng = SeededGenerator(seed: seed)
            let exercises = prepared.exercises(rng: &rng)
            #expect(exercises.map(\.kind) == prepared.steps.map(\.kind), "\(lesson.id)")
            #expect(exercises.map(\.id) == Array(exercises.indices))
            for (exercise, step) in zip(exercises, prepared.steps) {
                let label = "\(lesson.id), seed \(seed), шаг \(exercise.id) \(exercise.kind)"
                let bad = exercise.text.filter {
                    !(ctx.allowed.contains($0)
                      || ctx.capitals && $0.isUppercase && $0 != "Ё" && ctx.allowed.contains(Character($0.lowercased())))
                }
                #expect(bad.isEmpty, "\(label): лишние символы «\(bad)»")
                if exercise.kind == .errorWords {
                    let words = exercise.text.split(separator: " ")
                    #expect(words.count % 2 == 0 && (8...10).contains(words.count / 2), "\(label): \(exercise.text)")
                } else {
                    #expect(Double(exercise.text.count) >= 0.85 * Double(step.length),
                            "\(label): \(exercise.text.count) из \(step.length)")
                }
                // Связный текст — только у предложений и текстов на этапах с длиной text (решения 5, 8).
                let connectedKinds: Set<ExerciseKind> = step.focus == .strong ? [.sentences, .text, .check]
                    : [.sentences, .text, .check, .sprint]
                #expect(exercise.connected == (hasText(ctx) && connectedKinds.contains(exercise.kind)), "\(label)")
                if exercise.kind == .sprint && exercise.connected {
                    #expect(Double(exercise.text.count) <= 1.25 * Double(step.length), "\(label): \(exercise.text)")
                }
                #expect(exercise.title == step.title)
            }
        }
    }
}

@Test func reviewDrillsTheThreeLettersWithMostErrors() throws {
    var keys: [Character: KeyMastery] = [:]
    for letter in "аовлке" { keys[letter] = mastery(0) }
    keys["л"] = mastery(0.3)
    keys["в"] = mastery(0.2)
    keys["о"] = mastery(0.1)
    let prepared = try prepare("ru2.s1.04", learner: LearnerStats(keys: keys))
    #expect(prepared.weakKeys.prefix(3) == ["л", "в", "о"])
    var rng = SeededGenerator(seed: 7)
    let drill = try #require(prepared.exercises(rng: &rng).first)
    #expect(drill.kind == .drill)
    #expect(!drill.text.isEmpty && drill.text.allSatisfy { "лво ".contains($0) }, "\(drill.text)")
}

@Test func reviewWithoutDataTakesTheStagesNewKeys() throws {
    let prepared = try prepare("ru2.s1.04")
    #expect(prepared.weakKeys == ["а", "о", "в", "л"])
    #expect(prepared.weakBigrams.isEmpty)
}

/// «Ускорение» там, где открыто больше 6 букв: сильные — ровно 6 букв без ошибок при 40 нажатиях.
@Test func speedupBuildsWordsFromStrongLetters() throws {
    let course = try CourseFixtures.ruText()
    let ctx = try #require(course.context(for: "ru2.s4.04"))
    let open = ctx.allowed.filter { $0.isLetter && $0.isLowercase }
    #expect(open.count > 6)
    let strongLetters = Set("аовлке")
    var keys: [Character: KeyMastery] = [:]
    for letter in open { keys[letter] = mastery(strongLetters.contains(letter) ? 0 : 0.1) }
    let prepared = try prepare("ru2.s4.04", in: course, learner: LearnerStats(keys: keys))
    #expect(prepared.strongKeys == strongLetters.sorted())
    for seed in UInt64(1)...5 {
        var rng = SeededGenerator(seed: seed)
        let exercises = prepared.exercises(rng: &rng)
        #expect(exercises.map(\.kind) == [.words, .sprint, .sprint, .sprint, .text, .check])
        for step in exercises.prefix(4) {
            #expect(!step.text.isEmpty)
            for word in step.text.split(separator: " ") {
                let share = Double(word.filter(strongLetters.contains).count) / Double(word.count)
                #expect(share >= 0.8, "seed \(seed), шаг \(step.id): «\(word)»")
            }
        }
    }
    // Без статистики сильных нет — берутся все открытые буквы.
    #expect(try prepare("ru2.s4.04", in: course).strongKeys == open.sorted())
}

/// «Повтор» с данными, но с одной слабой буквой: до трёх добирают последние новые буквы этапа.
@Test func reviewWithFewWeakLettersIsPaddedToThree() throws {
    var keys: [Character: KeyMastery] = [:]
    for letter in "аовл" { keys[letter] = mastery(0) }
    keys["а"] = mastery(0.2)
    let prepared = try prepare("ru2.s1.04", learner: LearnerStats(keys: keys))
    #expect(prepared.weakKeys == ["а", "л", "в"])
}

/// Текст — целые предложения из `pieces` через пробел.
private func isSentences(_ text: String, from pieces: Set<String>) -> Bool {
    let tokens = text.split(separator: " ").map(String.init)
    let options = pieces.map { $0.split(separator: " ").map(String.init) }
    var reachable = Array(repeating: false, count: tokens.count + 1)
    reachable[0] = true
    for start in tokens.indices where reachable[start] {
        for piece in options where start + piece.count <= tokens.count
            && Array(tokens[start..<start + piece.count]) == piece {
            reachable[start + piece.count] = true
        }
    }
    return !tokens.isEmpty && reachable[tokens.count]
}

@Test func sentencesComeFromTheCorpusInStageStyle() throws {
    let course = try CourseFixtures.ruText()
    let prepared = try prepare("ru2.s4.02", in: course)
    let styled = Set(corpusTexts.compactMap {
        TextNormalizer.styled($0, style: .lowerPlain, allowed: prepared.context.allowed, capitals: false)
    })
    #expect(styled.count == corpusTexts.count)
    var rng = SeededGenerator(seed: 3)
    let exercises = prepared.exercises(rng: &rng)
    let sentences = exercises.filter { $0.kind == .sentences }
    #expect(sentences.count == 2)
    for step in sentences {
        #expect(step.connected)
        #expect(!step.text.contains { $0.isUppercase || $0.isPunctuation })
        #expect(isSentences(step.text, from: styled), "\(step.text)")
    }
    #expect(exercises.filter { $0.kind == .text || $0.kind == .check }.allSatisfy { $0.connected })
    #expect(exercises.filter { $0.kind == .words || $0.kind == .phrases }.allSatisfy { !$0.connected })
}

@Test func fewCorpusSentencesFallBackToTheGenerator() throws {
    let course = try CourseFixtures.ruText()
    let small = Array(corpus.prefix(5))
    let prepared = try prepare("ru2.s4.02", in: course, corpus: small)
    let styled = small.compactMap {
        TextNormalizer.styled($0.text, style: .lowerPlain, allowed: prepared.context.allowed, capitals: false)
    }
    for seed in UInt64(1)...5 {
        var rng = SeededGenerator(seed: seed)
        for step in prepared.exercises(rng: &rng) where step.kind == .sentences {
            #expect(step.connected)
            #expect(step.text.count >= 240)
            #expect(!styled.contains { step.text.contains($0) }, "\(step.text)")
        }
    }
}

@Test func classicsLessonTakesOnlyItsAuthor() throws {
    let course = try CourseFixtures.ruText()
    let prepared = try prepare("ru2.s4.03", in: course)
    let allowed = prepared.context.allowed
    let pushkinWords = Set(pushkin.flatMap { excerpt in
        TextNormalizer.sentences(excerpt.text).compactMap {
            TextNormalizer.styled($0, style: .lowerPlain, allowed: allowed, capitals: false)
        }.flatMap { $0.split(separator: " ").map(String.init) }
    })
    for seed in UInt64(1)...10 {
        var rng = SeededGenerator(seed: seed)
        let texts = prepared.exercises(rng: &rng).filter { $0.kind == .text || $0.kind == .check }
        #expect(texts.count == 3)
        for step in texts {
            #expect(step.connected)
            #expect(Double(step.text.count) >= 0.85 * 280, "\(step.text)")
            for word in step.text.split(separator: " ") {
                #expect(pushkinWords.contains(String(word)), "seed \(seed): «\(word)» не из Пушкина")
            }
        }
    }
}

@Test func plannerKeepsEditionOneAndDelegatesEditionTwo() throws {
    let course = try CourseFixtures.ruMini()
    let ctx = try #require(course.context(for: "ru2.s1.01"))
    let planner = LessonPlanner(generator: generator, corpus: corpus, library: pushkin)
    var a = SeededGenerator(seed: 11), b = SeededGenerator(seed: 11)
    #expect(planner.exercises(for: ctx, rng: &a) == planner.prepare(ctx, learner: .empty).exercises(rng: &b))
}

/// Связный текст не склеивает два отрывка, если отрывок длиннее шага.
@Test func connectedTextStaysInsideOneLongExcerpt() throws {
    let sea = LibraryText(id: "ru.test.sea", title: "Море", author: "Тест",
                          text: String(repeating: "Синее море шумит у скал. Белый парус уходит вдаль. Чайки кричат над волной. ",
                                       count: 6), source: "")
    let forest = LibraryText(id: "ru.test.forest", title: "Лес", author: "Тест",
                             text: String(repeating: "Старый лес молчит зимой. Под елью спит медведь. Снег лежит на ветках. ",
                                          count: 6), source: "")
    let course = try CourseFixtures.ruText()
    let prepared = try prepare("ru2.s4.02", in: course, library: [sea, forest])
    func vocabulary(_ excerpt: LibraryText) -> Set<String> {
        Set(TextNormalizer.sentences(excerpt.text).compactMap {
            TextNormalizer.styled($0, style: .lowerPlain, allowed: prepared.context.allowed, capitals: false)
        }.flatMap { $0.split(separator: " ").map(String.init) })
    }
    let seaWords = vocabulary(sea), forestWords = vocabulary(forest)
    for seed in UInt64(1)...20 {
        var rng = SeededGenerator(seed: seed)
        for step in prepared.exercises(rng: &rng) where step.kind == .text || step.kind == .check {
            let words = Set(step.text.split(separator: " ").map(String.init))
            #expect(words.isSubset(of: seaWords) || words.isSubset(of: forestWords), "seed \(seed): \(step.text)")
            #expect(Double(step.text.count) >= 0.85 * 280, "seed \(seed): \(step.text)")
        }
    }
}

// MARK: - «Трудные» уроки и «Освежить» (§6.3)

@Test func hardLettersOutweighTheirErrorShareInReview() throws {
    var keys: [Character: KeyMastery] = [:]
    for letter in "аовлке" { keys[letter] = mastery(0) }
    keys["л"] = mastery(0.05)
    keys["в"] = mastery(0.08)
    keys["о"] = mastery(0.04)
    #expect(try prepare("ru2.s1.04", learner: LearnerStats(keys: keys)).weakKeys.prefix(3) == ["в", "л", "о"])
    let boosted = LearnerStats(keys: keys, hardLetters: ["л"])
    #expect(try prepare("ru2.s1.04", learner: boosted).weakKeys.prefix(3) == ["л", "в", "о"])
}

@Test func refreshSpecIsTheLessonsCheckAsRefresh() throws {
    for (fixture, lessonId, connected) in [("mini", "ru2.s1.03", false), ("text", "ru2.s4.02", true)] {
        let course = try fixture == "mini" ? CourseFixtures.ruMini() : CourseFixtures.ruText()
        let ctx = try #require(course.context(for: lessonId))
        let planner = LessonPlanner(generator: generator, corpus: corpus, library: pushkin + [chekhov])
        var rng = SeededGenerator(seed: 5), same = SeededGenerator(seed: 5)
        let spec = try #require(planner.refreshSpec(for: ctx, learner: .empty, rng: &rng))
        let check = try #require(planner.exercises(for: ctx, rng: &same).last { $0.kind == .check })
        #expect(spec.kind == .refresh && spec.title == "Освежить" && spec.localizedTitle == CoreText.localized("Освежить"))
        #expect(spec.id == check.id && spec.text == check.text && !spec.text.isEmpty, "\(lessonId)")
        #expect(spec.connected == check.connected && spec.connected == connected, "\(lessonId)")
        let length = try #require(ctx.stage.lengths).length(for: .check)
        #expect(Double(spec.text.count) >= 0.85 * Double(length), "\(lessonId): \(spec.text.count) из \(length)")
    }
}

@Test func refreshSpecOfAnEditionOneLessonHasTheCheckLength() throws {
    let course = try CourseFixtures.editionOne(.ru)
    let planner = LessonPlanner(generator: TextGenerator(wordList: try WordList.load(.ru)))
    let ctx = try #require(course.context(for: "ru.1.1"))
    var rng = SeededGenerator(seed: 3)
    let spec = try #require(planner.refreshSpec(for: ctx, rng: &rng))
    #expect(spec.kind == .refresh && !spec.connected)
    #expect(Double(spec.text.count) >= 0.85 * Double(LessonPlanner.checkLength(targetCpm: ctx.targetCpm)))
}
