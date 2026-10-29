import Testing
@testable import TypingCore

// Шаблоны видов уроков и разрешение шагов (§2.2, §2.3; решения 4–7).

private func resolved(_ lessonId: String, in course: Course? = nil) throws -> [ResolvedStep] {
    let course = try course ?? CourseFixtures.ruMini()
    return StepTemplates.resolve(try #require(course.context(for: lessonId)))
}

@Test func keysLessonOnStageOne() throws {
    let steps = try resolved("ru2.s1.01")
    #expect(steps.map(\.kind) == [.drill, .combos, .words, .words, .phrases, .check])
    #expect(steps.map(\.length) == [30, 40, 50, 50, 60, 60])
    #expect(steps.map(\.title) == steps.map(\.kind.titleKey))
}

@Test func singleRowLesson() throws {
    let steps = try resolved("ru2.s1.03")
    #expect(steps.map(\.kind) == [.rowWords, .rowWords, .rowWords, .phrases, .focus, .phrases, .check])
    #expect(steps.prefix(3).allSatisfy { $0.rows == [.home] && $0.minShare == 1.0 })
}

@Test func reviewOnStageWithoutText() throws {
    let steps = try resolved("ru2.s1.04")
    #expect(steps.map(\.kind) == [.drill, .errorWords, .focus, .focus, .errorWords, .phrases, .check])
    #expect(steps.map(\.focus) == [.weakLetters, nil, .weakLetters, .weakBigrams, nil, nil, nil])
}

@Test func stageCheckHasWarmUpTextAndLongerCheck() throws {
    let steps = try resolved("ru2.s1.check")
    #expect(steps.map(\.kind) == [.words, .phrases, .check])
    #expect(steps.map(\.length) == [30, 60, 90])
    #expect(steps.map(\.title) == ["Разминка", "Фразы", "Проверочный текст"])
}

@Test func keysLessonOnStageTwoDrillsTheNewKeysRowWithHome() throws {
    let steps = try resolved("ru2.s2.01")
    #expect(steps.map(\.kind) == [.drill, .combos, .words, .focus, .rowWords, .phrases, .check])
    let rowStep = try #require(steps.first { $0.kind == .rowWords })
    #expect(rowStep.rows == [.top, .home])
    #expect(rowStep.minShare == 0.6)
}

@Test func speedupLessonWithoutText() throws {
    let steps = try resolved("ru2.s2.02")
    #expect(steps.map(\.kind) == [.words, .sprint, .sprint, .sprint, .phrases, .check])
    #expect(steps.map(\.length) == [100, 80, 80, 80, 120, 120])
    #expect(steps.map(\.focus) == [.strong, .strong, .strong, .strong, nil, nil])
}

@Test func tierLessonWithoutText() throws {
    let steps = try resolved("ru2.s2.04")
    #expect(steps.map(\.kind) == [.phrases, .phrases, .sprint, .phrases, .phrases, .check])
}

@Test func twoRowsLessonDrillsEachRowThenBoth() throws {
    let steps = try resolved("ru2.s2.03")
    #expect(steps.map(\.kind) == [.rowWords, .rowWords, .rowWords, .phrases, .focus, .phrases, .check])
    #expect(steps.prefix(3).map(\.rows) == [[.top], [.home], [.top, .home]])
    #expect(steps.prefix(3).map(\.minShare) == [1.0, 1.0, 0.6])
}

@Test func textLessonHasSevenStepsAndEightOnStageSeven() throws {
    let course = try CourseFixtures.ruText()
    let stage4 = try resolved("ru2.s4.02", in: course)
    #expect(stage4.map(\.kind) == [.words, .phrases, .sentences, .sentences, .text, .text, .check])
    #expect(stage4.map(\.length) == [200, 240, 240, 240, 280, 280, 280])
    let stage7 = try resolved("ru2.s7.01", in: course)
    #expect(stage7.map(\.kind) == [.words, .phrases, .sentences, .sentences, .text, .text, .text, .check])
    // Ключи этапа 4 — по шаблону этапов 5–6 (решение 7); проверка этапа 7 — 300 + 500 + 900.
    #expect(try resolved("ru2.s4.01", in: course).map(\.kind)
            == [.drill, .combos, .words, .sentences, .sentences, .text, .check])
    #expect(try resolved("ru2.s7.check", in: course).map(\.length) == [300, 500, 900])
}

@Test func lessonStepsOverrideTheTemplate() throws {
    let json = CourseFixtures.ruMiniJSON.replacingOccurrences(
        of: #""kind": "tier", "targetCpm": 100"#,
        with: #""kind": "tier", "targetCpm": 100, "steps": [{ "kind": "words", "length": 77 }, { "kind": "check" }]"#)
    let steps = try resolved("ru2.s2.04", in: try CourseFixtures.decode(json))
    #expect(steps.map(\.kind) == [.words, .check])
    #expect(steps.map(\.length) == [77, 120])
}
