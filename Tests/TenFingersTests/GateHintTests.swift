import Foundation
import Testing
import TypingCore
@testable import TenFingers

// MARK: - Текст порога

/// Проверка этапа 1 набрала ★ при пороге ★★: что нужно, чтобы открыть этап 2 (цель проверки — «до», 80 зн/мин).
@Test func gateHintNamesTheThresholdOfTheStage() throws {
    let course = try CourseFixtureApp.ruMini()
    #expect(GateHint.text(course: course, lessonId: "ru2.s1.check", checkStars: 1, unit: .cpm)
            == "Чтобы открыть этап 2, нужно ★★: не медленнее 64 зн/мин и не больше 3 ошибок на 100 знаков")
    #expect(GateHint.text(course: course, lessonId: "ru2.s1.check", checkStars: 1, unit: .wpm)
            == "Чтобы открыть этап 2, нужно ★★: не медленнее 13 WPM и не больше 3 ошибок на 100 знаков")
}

/// Итоговая проверка: «Чтобы пройти курс», порог ★★★ — цель проверки (110 зн/мин), не больше 2 ошибок на 100 знаков.
@Test func gateHintOfTheLastStageSaysCourse() throws {
    let course = try CourseFixtureApp.ruMini()
    #expect(GateHint.text(course: course, lessonId: "ru2.s2.check", checkStars: 2, unit: .cpm)
            == "Чтобы пройти курс, нужно ★★★: не медленнее 110 зн/мин и не больше 2 ошибок на 100 знаков")
}

/// Порог взят, урок не засчитан, не проверка этапа, урока нет — подсказки нет.
@Test func gateHintIsAbsentWhenThereIsNothingToSay() throws {
    let course = try CourseFixtureApp.ruMini()
    #expect(GateHint.text(course: course, lessonId: "ru2.s1.check", checkStars: 2, unit: .cpm) == nil)
    #expect(GateHint.text(course: course, lessonId: "ru2.s1.check", checkStars: 5, unit: .cpm) == nil)
    #expect(GateHint.text(course: course, lessonId: "ru2.s1.check", checkStars: 0, unit: .cpm) == nil)
    #expect(GateHint.text(course: course, lessonId: "ru2.s1.03", checkStars: 1, unit: .cpm) == nil)
    #expect(GateHint.text(course: course, lessonId: "нет такого", checkStars: 1, unit: .cpm) == nil)
}

/// Издание 1 порога не знает.
@Test func gateHintIsAbsentInEditionOne() throws {
    let course = try #require(try CourseCatalog.legacy(.ru))
    let check = try #require(course.stages.first?.checkLesson)
    #expect(GateHint.text(course: course, lessonId: check.id, checkStars: 1, unit: .cpm) == nil)
}

// MARK: - Порог по лучшей попытке

/// Раньше набранные ★★ остаются: слабая пересдача (★) не говорит, что этап 2 ещё закрыт, и кнопки не будет.
@Test func gateHintUsesTheBestStarsNotOnlyTheAttempt() throws {
    let course = try CourseFixtureApp.ruMini()
    let threshold = "Чтобы открыть этап 2, нужно ★★: не медленнее 64 зн/мин и не больше 3 ошибок на 100 знаков"
    // Порог уже взят (★★ в истории) — слабая попытка ★ подсказки не даёт, ни с попыткой в истории, ни без неё.
    #expect(GateHint.text(course: course, lessonId: "ru2.s1.check", attemptStars: 1,
                          storedCheckStars: ["ru2.s1.check": 2], unit: .cpm) == nil)
    // Порога ещё нет: первая попытка ★ — подсказка; в истории ★ (с этой попыткой) — тоже.
    #expect(GateHint.text(course: course, lessonId: "ru2.s1.check", attemptStars: 1,
                          storedCheckStars: [:], unit: .cpm) == threshold)
    #expect(GateHint.text(course: course, lessonId: "ru2.s1.check", attemptStars: 1,
                          storedCheckStars: ["ru2.s1.check": 1], unit: .cpm) == threshold)
    // Попытка не засчитана (0 звёзд) — подсказки нет, даже когда порога в истории нет.
    #expect(GateHint.text(course: course, lessonId: "ru2.s1.check", attemptStars: 0,
                          storedCheckStars: [:], unit: .cpm) == nil)
    // Последний этап: курс уже пройден (★★★ в истории) — «Чтобы пройти курс» не показывается.
    #expect(GateHint.text(course: course, lessonId: "ru2.s2.check", attemptStars: 2,
                          storedCheckStars: ["ru2.s2.check": 3], unit: .cpm) == nil)
    #expect(GateHint.text(course: course, lessonId: "ru2.s2.check", attemptStars: 2,
                          storedCheckStars: ["ru2.s2.check": 2], unit: .cpm)?.hasPrefix("Чтобы пройти курс") == true)
}

/// Повтор одной проверки этапа (экран итога шага) строит подсказку тем же путём: ★★ в истории, попытка ★ — без неё;
/// у шага, который не проверка этапа (попытка 0), и у обычного урока подсказки нет.
@Test func gateHintOfASingleStepReplayFollowsTheSameRule() throws {
    let course = try CourseFixtureApp.ruMini()
    #expect(GateHint.text(course: course, lessonId: "ru2.s1.check", attemptStars: 1,
                          storedCheckStars: ["ru2.s1.check": 2], unit: .cpm) == nil)
    #expect(GateHint.text(course: course, lessonId: "ru2.s1.check", attemptStars: 1,
                          storedCheckStars: ["ru2.s1.check": 1], unit: .cpm) != nil)
    #expect(GateHint.text(course: course, lessonId: "ru2.s1.03", attemptStars: 1,
                          storedCheckStars: [:], unit: .cpm) == nil)
}

// MARK: - «Потренировать слабые буквы»

/// Кнопка ведёт в последний «Повтор» этапа; в этапе без «Повтора» (этап 2 мини-курса) кнопки нет.
@Test func reviewLessonIsTheLastReviewOfTheStage() throws {
    let course = try CourseFixtureApp.ruMini()
    #expect(GateHint.reviewLesson(course: course, checkLessonId: "ru2.s1.check")?.id == "ru2.s1.04")
    #expect(GateHint.reviewLesson(course: course, checkLessonId: "ru2.s2.check") == nil)
    #expect(GateHint.reviewLesson(course: course, checkLessonId: "нет такого") == nil)
}

// MARK: - «Следующий урок» по гейту

/// Следующий урок открыт по гейту с учётом этой попытки: проверка ниже порога не ведёт в закрытый этап.
@Test func nextLessonFollowsTheGate() throws {
    let course = try CourseFixtureApp.ruMini()
    // Обычный урок этапа: следующий открыт, как только засчитан этот.
    #expect(GateHint.nextLesson(course: course, after: "ru2.s1.01", stars: 1, passed: [], checkStars: [:])?.id == "ru2.s1.02")
    #expect(GateHint.nextLesson(course: course, after: "ru2.s1.01", stars: 0, passed: [], checkStars: [:]) == nil)
    // Проверка этапа 1: ★ (порог ★★) — этап 2 закрыт; ★★ — открыт.
    #expect(GateHint.nextLesson(course: course, after: "ru2.s1.check", stars: 1, passed: [], checkStars: [:]) == nil)
    #expect(GateHint.nextLesson(course: course, after: "ru2.s1.check", stars: 2, passed: [], checkStars: [:])?.id == "ru2.s2.01")
    // Раньше набранный порог остаётся: слабая попытка его не отменяет.
    #expect(GateHint.nextLesson(course: course, after: "ru2.s1.check", stars: 1, passed: [],
                                checkStars: ["ru2.s1.check": 2])?.id == "ru2.s2.01")
    // Последний урок курса — следующего нет.
    #expect(GateHint.nextLesson(course: course, after: "ru2.s2.check", stars: 3, passed: [], checkStars: [:]) == nil)
}

/// Издание 1: следующий урок открыт, если засчитан этот.
@Test func nextLessonInEditionOneIgnoresTheGate() throws {
    let course = try #require(try CourseCatalog.legacy(.ru))
    let first = course.lessons[0].id, second = course.lessons[1].id
    #expect(GateHint.nextLesson(course: course, after: first, stars: 1, passed: [], checkStars: [:])?.id == second)
    #expect(GateHint.nextLesson(course: course, after: first, stars: 0, passed: [], checkStars: [:]) == nil)
}
