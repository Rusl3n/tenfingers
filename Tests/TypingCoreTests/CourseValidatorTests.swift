import Foundation
import Testing
@testable import TypingCore

// Проверка структуры курса издания 2: каждая порча мини-курса даёт сообщение с id.

private let ruMiniKeys = Set("аовлке")

/// Нарушения копии мини-курса, испорченной заменой строки `of` на `with` (строка обязана найтись).
private func problems(replacing of: String, with: String, expectedKeys: Set<Character> = ruMiniKeys) throws
    -> [String] {
    #expect(CourseFixtures.ruMiniJSON.contains(of), "в фикстуре нет «\(of)»")
    let course = try CourseFixtures.decode(CourseFixtures.ruMiniJSON.replacingOccurrences(of: of, with: with))
    return CourseValidator.problems(course, expectedKeys: expectedKeys)
}

@Test func validFixtureHasNoProblems() throws {
    #expect(CourseValidator.problems(try CourseFixtures.ruMini(), expectedKeys: ruMiniKeys) == [])
}

@Test func repeatedKeyIsReported() throws {
    let found = try problems(replacing: #""newKeys": ["в", "л"]"#, with: #""newKeys": ["в", "л", "а"]"#)
    #expect(found.count == 1 && found.allSatisfy { $0.contains("«а»") && $0.contains("ru2.s1.02") }, "\(found)")
}

@Test func checkMustBeLastLessonOfStage() throws {
    let check = #"{ "id": "ru2.s1.check", "title": "Проверка этапа", "kind": "stageCheck", "hint": "onError" }"#
    let found = try problems(replacing: check,
                             with: check + #", { "id": "ru2.s1.06", "title": "Связный текст", "kind": "text" }"#)
    #expect(found.count == 1 && found.allSatisfy { $0.contains("ru2.s1") }, "\(found)")
}

@Test func reviewAndSpeedupMustAlternate() throws {
    let found = try problems(replacing: #""kind": "speedup""#, with: #""kind": "review""#)
    #expect(found.count == 1 && found.allSatisfy { $0.contains("ru2.s2.02") }, "\(found)")
}

@Test func lessonIdNeedsTwoDigits() throws {
    let found = try problems(replacing: #""id": "ru2.s1.03""#, with: #""id": "ru2.s1.3""#)
    #expect(found.count == 1 && found.allSatisfy { $0.contains("ru2.s1.3") }, "\(found)")
}

@Test func missingExpectedKeyIsReported() throws {
    let found = CourseValidator.problems(try CourseFixtures.ruMini(), expectedKeys: ruMiniKeys.union(["ж"]))
    #expect(found.count == 1 && found.allSatisfy { $0.contains("«ж»") }, "\(found)")
}

/// Ровно одно сообщение, и в нём есть `fragment`.
private func expectSingle(_ found: [String], _ fragment: String, sourceLocation: SourceLocation = #_sourceLocation) {
    #expect(found.count == 1 && found.allSatisfy { $0.contains(fragment) }, "\(found)", sourceLocation: sourceLocation)
}

@Test func structuralFieldsAreChecked() throws {
    // Урок rows без рядов, ступень без цели, урок keys без клавиш, порог вне 1…5, «до» меньше «от», издание.
    expectSingle(try problems(replacing: #", "rows": ["home"]"#, with: ""), "нужно 1–3 ряда")
    expectSingle(try problems(replacing: #", "targetCpm": 100"#, with: ""), "нет цели (targetCpm)")
    expectSingle(try problems(replacing: #""newKeys": ["к", "е"]"#, with: #""newKeys": []"#,
                              expectedKeys: Set("аовл")), "нет newKeys, capitals и focus")
    expectSingle(try problems(replacing: #""gateStars": 2"#, with: #""gateStars": 6"#), "порог 6 вне")
    expectSingle(try problems(replacing: #""targetCpmEnd": 110"#, with: #""targetCpmEnd": 80"#), "меньше «от»")
    expectSingle(try problems(replacing: #""edition": 2"#, with: #""edition": 1"#), "издание курса 1")
}

@Test func lessonRowsMustNotRepeat() throws {
    expectSingle(try problems(replacing: #""rows": ["top", "home"]"#, with: #""rows": ["home", "home"]"#),
                 "ряды повторяются")
}

@Test func keyOutsideExpectedKeysIsReported() throws {
    let found = CourseValidator.problems(try CourseFixtures.ruMini(), expectedKeys: ruMiniKeys.subtracting(["е"]))
    expectSingle(found, "«е» (урок ru2.s2.01) не входит в клавиши курса")
}

@Test func longCourseWithoutReviewsIsReported() throws {
    // Без «Повтора» и «Ускорения» вовсе: 10 уроков (больше 6) — одно сообщение.
    var json = CourseFixtures.ruMiniJSON
    for (of, with) in [(#""kind": "review""#, #""kind": "text""#), (#""kind": "speedup""#, #""kind": "text""#)] {
        #expect(json.contains(of))
        json = json.replacingOccurrences(of: of, with: with)
    }
    expectSingle(CourseValidator.problems(try CourseFixtures.decode(json), expectedKeys: ruMiniKeys),
                 "нет «Повтора» и «Ускорения»")
}

@Test func lessonStepCountIsChecked() throws {
    let five = #"[{ "kind": "words" }, { "kind": "words" }, { "kind": "phrases" }, { "kind": "phrases" }, { "kind": "check" }]"#
    expectSingle(try problems(replacing: #""kind": "tier", "targetCpm": 100"#,
                              with: #""kind": "tier", "targetCpm": 100, "steps": "# + five), "ru2.s2.04: 5 шагов")
    let four = #"[{ "kind": "words" }, { "kind": "text" }, { "kind": "text" }, { "kind": "check" }]"#
    expectSingle(try problems(replacing: #""kind": "stageCheck", "hint": "onError""#,
                              with: #""kind": "stageCheck", "hint": "onError", "steps": "# + four), "ru2.s1.check: 4 шага")
}
