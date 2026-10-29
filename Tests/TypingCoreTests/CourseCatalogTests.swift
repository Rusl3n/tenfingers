import Foundation
import Testing
@testable import TypingCore

// Каталог курсов издания 2 (спецификация фазы 6, §2.1, §2.6): структура, генерация всех уроков, ресурсы.

enum CourseExpectations {
    static let ruKeys: Set<Character> = Set("абвгдеёжзийклмнопрстуфхцчшщъыьэюя1234567890.,-?!:;\"()№%*+=/")
    static let lessonCounts = [8, 14, 16, 12, 15, 15, 18]
    static let tiers: [[Int]] = [[], [100], [120], [140], [160], [170], [200, 250, 300]]
}

/// Символ шага допустим: открытый, или заглавная открытой буквы, когда заглавные изучены (кроме «Ё»).
func isTypeable(_ c: Character, _ ctx: LessonContext) -> Bool {
    if ctx.allowed.contains(c) { return true }
    guard ctx.capitals, c.isUppercase, c != "Ё", let lower = c.lowercased().first else { return false }
    return ctx.allowed.contains(lower)
}

/// Генерация всех уроков языка: 20 семян, только открытые символы, длины по этапу (§2.6).
func checkGeneratedCourse(_ language: Language) throws {
    let course = try CourseCatalog.load(language)
    let planner = LessonPlanner(generator: TextGenerator(wordList: try WordList.load(language)),
                                corpus: try SentenceCorpus.load(language), library: try TextLibrary.load(language))
    for lesson in course.lessons {
        let ctx = try #require(course.context(for: lesson.id))
        let prepared = planner.prepare(ctx, learner: .empty)
        for seed in 1...20 {
            var rng = SeededGenerator(seed: UInt64(seed))
            let plan = prepared.exercises(rng: &rng)
            #expect(plan.count == prepared.steps.count)
            for (spec, step) in zip(plan, prepared.steps) {
                let bad = spec.text.filter { !isTypeable($0, ctx) }
                #expect(bad.isEmpty, "\(lesson.id) шаг \(spec.id) \(spec.kind): «\(String(Set(bad)))»")
                if spec.kind != .errorWords {
                    #expect(spec.text.count >= step.length * 85 / 100, "\(lesson.id) шаг \(spec.id): \(spec.text.count) < \(step.length)")
                    // Предложения не режутся посередине: перебор — до одного предложения корпуса (≤ 140 знаков).
                    let slack = spec.kind == .sentences || spec.kind == .sprint ? 150 : max(30, step.length / 5)
                    #expect(spec.text.count <= step.length + slack, "\(lesson.id) шаг \(spec.id)")
                }
            }
        }
    }
}

@Test func russianCourseStructure() throws {
    let course = try CourseCatalog.load(.ru)
    #expect(CourseValidator.problems(course, expectedKeys: CourseExpectations.ruKeys) == [])
    #expect(course.lessons.count == 98)
    #expect(course.stages.map(\.lessons.count) == CourseExpectations.lessonCounts)
    #expect(course.stages.map { $0.lessons.filter { $0.resolvedKind == .tier }.compactMap(\.targetCpm) } == CourseExpectations.tiers)
    #expect(course.stages.map(\.gate) == [2, 3, 3, 3, 3, 3, 3])
    #expect(course.stages.map { [$0.targetCpm, $0.targetEnd] }
            == [[60, 80], [90, 110], [110, 130], [130, 150], [140, 170], [150, 180], [200, 220]])
    for stage in course.stages {
        let regular = stage.lessons.filter { $0.resolvedKind.isRegular }
        #expect(course.targetCpm(for: regular.first!.id) == stage.targetCpm)
        #expect(course.targetCpm(for: regular.last!.id) == stage.targetEnd)
        #expect(course.targetCpm(for: stage.checkLesson!.id) == stage.targetEnd)
    }
    #expect(try CourseCatalog.legacy(.ru)?.lessons.count == 30)
}

@Test func russianCourseGeneratesOnlyTypeableTextOfStageLength() throws { try checkGeneratedCourse(.ru) }

@Test func russianCorpusAndLibraryAreBundled() throws {
    let corpus = try SentenceCorpus.load(.ru)
    #expect((1500...2500).contains(corpus.count) && corpus.allSatisfy { $0.source.hasPrefix("tatoeba:") })
    let library = try TextLibrary.load(.ru)
    #expect(library.count >= 50 && library.contains { $0.id == "ru.pushkin.captains-daughter" })
    for prefix in ["ru.pushkin.", "ru.chekhov.", "ru.tolstoy."] {
        #expect(library.filter { $0.id.hasPrefix(prefix) }.reduce(0) { $0 + $1.text.count } >= 2500, "\(prefix)")
    }
}

extension CourseExpectations {
    static let enKeys: Set<Character> = Set("abcdefghijklmnopqrstuvwxyz1234567890;,.'-?!:\"()#$%@&^*+=/[]_")
}

@Test func englishCourseStructure() throws {
    let course = try CourseCatalog.load(.en)
    #expect(CourseValidator.problems(course, expectedKeys: CourseExpectations.enKeys) == [])
    #expect(course.lessons.count == 98)
    #expect(course.stages.map(\.lessons.count) == CourseExpectations.lessonCounts)
    #expect(course.stages.map { $0.lessons.filter { $0.resolvedKind == .tier }.compactMap(\.targetCpm) } == CourseExpectations.tiers)
    #expect(course.stages.map(\.gate) == [2, 3, 3, 3, 3, 3, 3])
    #expect(course.stages.map { [$0.targetCpm, $0.targetEnd] }
            == [[60, 80], [90, 110], [110, 130], [130, 150], [140, 170], [150, 180], [200, 220]])
    for stage in course.stages {
        let regular = stage.lessons.filter { $0.resolvedKind.isRegular }
        #expect(course.targetCpm(for: regular.first!.id) == stage.targetCpm)
        #expect(course.targetCpm(for: regular.last!.id) == stage.targetEnd)
        #expect(course.targetCpm(for: stage.checkLesson!.id) == stage.targetEnd)
    }
    #expect(try CourseCatalog.legacy(.en)?.lessons.count == 30)
}

@Test func englishCourseGeneratesOnlyTypeableTextOfStageLength() throws { try checkGeneratedCourse(.en) }

@Test func englishCorpusAndLibraryAreBundled() throws {
    let corpus = try SentenceCorpus.load(.en)
    #expect((1500...2500).contains(corpus.count) && corpus.allSatisfy { $0.source.hasPrefix("tatoeba:") })
    let library = try TextLibrary.load(.en)
    #expect(library.count >= 50)
    for prefix in ["en.dickens.", "en.twain.", "en.austen."] {
        #expect(library.filter { $0.id.hasPrefix(prefix) }.reduce(0) { $0 + $1.text.count } >= 2500, "\(prefix)")
    }
}

/// Ритм курсов один (§2.1, решение 12): в каждом этапе столько же уроков, «Повтор», «Ускорение», ступени
/// и проверка — на тех же местах, ступени — те же.
@Test func bothCoursesShareRhythm() throws {
    let ru = try CourseCatalog.load(.ru), en = try CourseCatalog.load(.en)
    #expect(ru.stages.count == en.stages.count)
    let fixed: Set<LessonKind> = [.review, .speedup, .tier, .stageCheck]
    for (ruStage, enStage) in zip(ru.stages, en.stages) {
        #expect(ruStage.lessons.count == enStage.lessons.count, "\(enStage.id)")
        let rhythm = { (stage: Stage) in
            stage.lessons.enumerated().filter { fixed.contains($0.element.resolvedKind) }
                .map { "\($0.offset):\($0.element.resolvedKind):\($0.element.targetCpm ?? 0)" }
        }
        #expect(rhythm(ruStage) == rhythm(enStage), "\(enStage.id)")
    }
}

/// Шаг «только ряд» (`rowWords` с долей 1,0) строится из слов ряда: среди открытых букв ряда есть гласная, иначе
/// получаются одни псевдослова из согласных (английский нижний ряд — урок с долей 0,5).
@Test func singleRowStepsHaveAVowel() throws {
    let vowels: [Language: Set<Character>] = [.ru: Set("аеёиоуыэюя"), .en: Set("aeiouy")]
    for language in Language.allCases {
        let course = try CourseCatalog.load(language)
        for lesson in course.lessons {
            let ctx = try #require(course.context(for: lesson.id))
            for (index, step) in StepTemplates.resolve(ctx).enumerated()
            where step.kind == .rowWords && (step.minShare ?? 1) >= 1 {
                let letters = step.rows.reduce(into: Set<Character>()) { $0.formUnion(ctx.rows[$1] ?? []) }
                    .intersection(ctx.allowed)
                #expect(!letters.isDisjoint(with: vowels[language] ?? []),
                        "\(lesson.id) шаг \(index): ряды \(step.rows) — «\(String(letters.sorted()))»")
            }
        }
    }
}

/// «Классика»: связный текст разных шагов урока — из разных отрывков, когда отрывков не меньше таких шагов.
@Test func classicsStepsUseDifferentExcerpts() throws {
    for language in Language.allCases {
        let course = try CourseCatalog.load(language)
        let library = try TextLibrary.load(language)
        let planner = LessonPlanner(generator: TextGenerator(wordList: try WordList.load(language)),
                                    corpus: try SentenceCorpus.load(language), library: library)
        let classics = course.lessons.filter { $0.textSource != nil }
        #expect(classics.count == 3)
        for lesson in classics {
            let source = try #require(lesson.textSource)
            let prepared = planner.prepare(try #require(course.context(for: lesson.id)), learner: .empty)
            for seed in 1...20 {
                var rng = SeededGenerator(seed: UInt64(seed))
                let texts = prepared.exercises(rng: &rng).filter(\.connected).filter { $0.kind != .sentences }
                    .map(\.text)
                try #require(library.filter { $0.id.hasPrefix(source) }.count >= texts.count)
                // Шаги из одного отрывка перекрываются: начало одного находится в другом.
                for (i, a) in texts.enumerated() {
                    for (j, b) in texts.enumerated() where i != j {
                        #expect(!b.contains(a.prefix(40)), "\(lesson.id) семя \(seed): шаги \(i) и \(j)")
                    }
                }
            }
        }
    }
}

/// Этап 4 (пунктуация `none`): шаги `words` — без знаков препинания, только буквы, пробелы и апостроф внутри слова.
@Test func stageFourWordsHaveNoPunctuation() throws {
    for language in Language.allCases {
        let course = try CourseCatalog.load(language)
        let planner = LessonPlanner(generator: TextGenerator(wordList: try WordList.load(language)),
                                    corpus: try SentenceCorpus.load(language), library: try TextLibrary.load(language))
        let stage = course.stages[3]
        #expect(stage.textStyle?.punctuation == PunctuationStyle.none)
        for lesson in stage.lessons {
            let prepared = planner.prepare(try #require(course.context(for: lesson.id)), learner: .empty)
            for seed in 1...20 {
                var rng = SeededGenerator(seed: UInt64(seed))
                for spec in prepared.exercises(rng: &rng) where spec.kind == .words {
                    let chars = Array(spec.text)
                    let bad = chars.indices.filter { index in
                        let c = chars[index]
                        guard !c.isLetter && c != " " else { return false }
                        return !(c == "'" && index > 0 && index < chars.count - 1
                                 && chars[index - 1].isLetter && chars[index + 1].isLetter)
                    }
                    #expect(bad.isEmpty, "\(lesson.id) шаг \(spec.id) семя \(seed): «\(String(bad.map { chars[$0] }))»")
                }
            }
        }
    }
}

/// Встроенный курс языка, у которого урок `lessonId` — другого вида: в этапе 1 нет «Ускорения», а план его текста
/// строится так же, как на остальных этапах.
private func catalogCourse(_ language: Language, lessonId: String, becomes kind: String) throws -> Course {
    let data = try Data(contentsOf: CoreResources.url("course-\(language.rawValue)", "json"))
    var root = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    var stages = try #require(root["stages"] as? [[String: Any]])
    for stageIndex in stages.indices {
        var lessons = try #require(stages[stageIndex]["lessons"] as? [[String: Any]])
        for index in lessons.indices where lessons[index]["id"] as? String == lessonId { lessons[index]["kind"] = kind }
        stages[stageIndex]["lessons"] = lessons
    }
    root["stages"] = stages
    return try JSONDecoder().decode(Course.self, from: JSONSerialization.data(withJSONObject: root))
}

/// Ученик с историей по всему алфавиту: буквы, которых в этапе 1 ещё нет, — самые ошибочные (для «Повтора») либо самые
/// сильные (для «Ускорения»); так же с парами букв. В текст этапа 1 они попасть не должны: ни слабые, ни сильные,
/// ни биграммы, ни сам текст шага.
@Test func fullAlphabetLearnerDoesNotLeakClosedLettersIntoStageOne() throws {
    for language in Language.allCases {
        let planner = LessonPlanner(generator: TextGenerator(wordList: try WordList.load(language)),
                                    corpus: try SentenceCorpus.load(language), library: try TextLibrary.load(language))
        let reviewId = "\(language.rawValue)2.s1.07", speedupId = "\(language.rawValue)2.s1.06"
        let courses = [
            (reviewId, try catalogCourse(language, lessonId: reviewId, becomes: "review")),
            (speedupId, try catalogCourse(language, lessonId: speedupId, becomes: "speedup")),
        ]
        for (lessonId, course) in courses {
            let ctx = try #require(course.context(for: lessonId))
            #expect(ctx.lesson.resolvedKind == (lessonId == reviewId ? .review : .speedup))
            let letters = language.letters.sorted()
            let closed = letters.filter { !ctx.allowed.contains($0) }
            #expect(closed.count > 10, "\(language): в этапе 1 закрыто мало букв")
            for strong in [false, true] {
                var keys: [Character: KeyMastery] = [:]
                var bigrams: [String: KeyMastery] = [:]
                for letter in letters {
                    let isClosed = closed.contains(letter)
                    let rate = strong ? (isClosed ? 0 : 0.2) : (isClosed ? 0.6 : 0.1)
                    keys[letter] = KeyMastery(ewmaMs: 250, errorRate: rate, presses: 200)
                }
                for (a, b) in zip(letters, letters.dropFirst()) {
                    let rate = strong ? (closed.contains(a) || closed.contains(b) ? 0 : 0.2)
                                      : (closed.contains(a) || closed.contains(b) ? 0.6 : 0.1)
                    bigrams[String([a, b])] = KeyMastery(ewmaMs: 250, errorRate: rate, presses: 200)
                }
                let prepared = planner.prepare(ctx, learner: LearnerStats(keys: keys, bigrams: bigrams))
                let label = "\(lessonId), \(strong ? "сильные" : "слабые")"
                // Данные есть, но отбор идёт среди открытых: слабые и сильные буквы этапа не пусты.
                #expect(!prepared.weakKeys.isEmpty && !prepared.strongKeys.isEmpty, "\(label)")
                #expect(prepared.weakKeys.allSatisfy { ctx.allowed.contains($0) }, "\(label): weakKeys")
                #expect(prepared.strongKeys.allSatisfy { ctx.allowed.contains($0) }, "\(label): strongKeys")
                #expect(prepared.weakBigrams.allSatisfy { $0.allSatisfy { ctx.allowed.contains($0) } }, "\(label): bigrams")
                for seed in 1...10 {
                    var rng = SeededGenerator(seed: UInt64(seed))
                    let plan = prepared.exercises(rng: &rng)
                    #expect(!plan.isEmpty)
                    for spec in plan {
                        let bad = spec.text.filter { !isTypeable($0, ctx) }
                        #expect(bad.isEmpty, "\(label) шаг \(spec.id) \(spec.kind) семя \(seed): «\(String(Set(bad)))»")
                        #expect(!spec.text.isEmpty)
                    }
                }
            }
        }
    }
}
