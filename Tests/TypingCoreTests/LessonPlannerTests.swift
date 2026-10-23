import Testing
@testable import TypingCore

@Test(arguments: Language.allCases)
func everyLessonProducesValidExercises(language: Language) throws {
    let course = try CourseCatalog.load(language)
    let planner = LessonPlanner(generator: TextGenerator(wordList: try WordList.load(language)))
    for lesson in course.lessons {
        let ctx = try #require(course.context(for: lesson.id))
        var rng = SeededGenerator(seed: 2026)
        let exercises = planner.exercises(for: ctx, rng: &rng)
        #expect(exercises.last?.kind == .check, "\(lesson.id)")
        let upper = ctx.capitals ? Set(ctx.allowed.filter(\.isLetter).flatMap { $0.uppercased() }) : []
        for exercise in exercises {
            #expect(!exercise.text.isEmpty, "\(lesson.id) \(exercise.kind)")
            let bad = exercise.text.filter { !ctx.allowed.contains($0) && !upper.contains($0) }
            #expect(bad.isEmpty, "\(lesson.id) \(exercise.kind): лишние символы «\(bad)»")
        }
        let check = exercises.last!.text
        for key in lesson.newCharacters {
            #expect(check.contains(key), "\(lesson.id): в проверочном тексте нет «\(key)»")
        }
    }
}

@Test func lessonWithNewKeysHasFourSteps() throws {
    let course = try CourseCatalog.load(.ru)
    let planner = LessonPlanner(generator: TextGenerator(wordList: try WordList.load(.ru)))
    var rng = SeededGenerator(seed: 1)
    let kinds = planner.exercises(for: try #require(course.context(for: "ru.1.1")), rng: &rng).map(\.kind)
    #expect(kinds == [.drill, .combos, .words, .check])
}

@Test func checkLessonHasOnlyCheck() throws {
    let course = try CourseCatalog.load(.ru)
    let planner = LessonPlanner(generator: TextGenerator(wordList: try WordList.load(.ru)))
    var rng = SeededGenerator(seed: 1)
    let kinds = planner.exercises(for: try #require(course.context(for: "ru.1.check")), rng: &rng).map(\.kind)
    #expect(kinds == [.check])
}

@Test func checkLengthScalesWithTarget() {
    #expect(LessonPlanner.checkLength(targetCpm: 60) == 90)
    #expect(LessonPlanner.checkLength(targetCpm: 180) == 270)
    #expect(LessonPlanner.checkLength(targetCpm: 400) == 300)
}

@Test(arguments: [(Language.ru, "ru.2.6"), (Language.ru, "ru.5.4"), (Language.en, "en.5.5"), (Language.en, "en.4.4")])
func newKeysAppearInCheckTextForManySeeds(language: Language, lessonId: String) throws {
    let course = try CourseCatalog.load(language)
    let planner = LessonPlanner(generator: TextGenerator(wordList: try WordList.load(language)))
    let ctx = try #require(course.context(for: lessonId))
    for seed in UInt64(1)...30 {
        var rng = SeededGenerator(seed: seed)
        let check = try #require(planner.exercises(for: ctx, rng: &rng).last?.text)
        for key in ctx.lesson.newCharacters {
            #expect(check.contains(key), "\(lessonId), seed \(seed): в проверочном тексте нет «\(key)»")
        }
    }
}
