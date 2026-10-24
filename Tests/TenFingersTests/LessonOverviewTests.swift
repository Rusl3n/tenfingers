import Foundation
import SwiftData
import Testing
import TypingCore
@testable import TenFingers

private func check(_ lessonId: String, accuracy: Double, cpm: Double, kind: String = "check",
                   completed: Bool = true) -> SessionRecord {
    let end = Date(timeIntervalSince1970: 1_773_144_000)
    return SessionRecord(mode: "course", language: "ru", lessonId: lessonId, startedAt: end.addingTimeInterval(-60),
                         endedAt: end, logicalDay: "2026-03-10", activeSeconds: 60, chars: Int(cpm), errorCount: 1,
                         cpm: cpm, accuracy: accuracy, completed: completed, hintLevel: "full", maxErrorStreak: 0,
                         wrongKeystrokes: 0, exerciseKind: kind)
}

@MainActor @Test func starsAreRecomputedFromHistoryNotStoredBest() throws {
    let container = try ModelStore.makeContainer(inMemory: true)
    defer { withExtendedLifetime(container) {} }
    let context = container.mainContext
    // Старая база: записано ★★★ (прежняя шкала), а по истории — ★★★: (120; 99%) — ★★★, (200; 97%) — ★★.
    let progress = LessonProgress(lessonId: "ru.1.1", language: "ru")
    progress.bestStars = 3
    progress.passedAt = .now
    context.insert(progress)
    context.insert(check("ru.1.1", accuracy: 0.99, cpm: 120))
    context.insert(check("ru.1.1", accuracy: 0.97, cpm: 200))
    try context.save()

    let sessions = try ProgressSnapshot(context: context).lessonSessions(lessonId: "ru.1.1")
    let overview = LessonOverview.make(lessonId: "ru.1.1", targetCpm: 60, sessions: sessions, storedStars: progress.bestStars)
    #expect(overview.stars == 3)
    #expect(progress.bestStars == 3) // данные пользователя не меняются
}

@Test func historyWithPerfectFastCheckGivesFiveStars() {
    let sessions = [
        SessionSummary(day: "d", endedAt: .now, language: .ru, mode: .course, chars: 90, activeSeconds: 60,
                       accuracy: 1.0, completed: true, lessonId: "ru.1.1", exerciseKind: .check, cpm: 90),
        SessionSummary(day: "d", endedAt: .now, language: .ru, mode: .course, chars: 120, activeSeconds: 60,
                       accuracy: 0.97, completed: true, lessonId: "ru.1.1", exerciseKind: .check, cpm: 120),
    ]
    #expect(LessonOverview.make(lessonId: "ru.1.1", targetCpm: 60, sessions: sessions, storedStars: 0).stars == 5)
}

@Test func withoutCheckHistoryStoredStarsAreKept() {
    // Проверок в истории нет (например, записи старых версий без шага): звёзды из базы не теряются
    // (хранятся в прежней шкале: 2 → ★★★).
    let overview = LessonOverview.make(lessonId: "ru.1.1", targetCpm: 60, sessions: [], storedStars: 2)
    #expect(overview.stars == 3)
    #expect(overview.steps.isEmpty && overview.errors == nil)
}

@Test func overviewHasStepsAndTotalErrors() {
    let sessions = [
        SessionSummary(day: "d", endedAt: .now, language: .ru, mode: .course, chars: 80, activeSeconds: 60,
                       accuracy: 1.0, completed: true, lessonId: "ru.1.1", exerciseKind: .drill, cpm: 80),
        SessionSummary(day: "d", endedAt: .now, language: .ru, mode: .course, chars: 80, activeSeconds: 60,
                       accuracy: 0.946, completed: true, lessonId: "ru.1.1", exerciseKind: .words, cpm: 80,
                       errorCount: 5),
    ]
    let overview = LessonOverview.make(lessonId: "ru.1.1", targetCpm: 60, sessions: sessions, storedStars: 0)
    #expect(overview.steps.map(\.kind) == [.drill, .words])
    #expect(overview.errors == 5)
    #expect(overview.stars == 0)
}

/// Урок пройден до появления шагов в истории (или проверки после — неудачные): не меньше одной звезды.
@Test func passedLessonShowsAtLeastOneStar() {
    #expect(LessonOverview.make(lessonId: "ru.1.1", targetCpm: 60, sessions: [], storedStars: 0, isPassed: true).stars == 1)
    let failedCheck = SessionSummary(day: "d", endedAt: .now, language: .ru, mode: .course, chars: 60, activeSeconds: 60,
                                     accuracy: 0.9, completed: true, lessonId: "ru.1.1", exerciseKind: .check, cpm: 60)
    #expect(LessonOverview.make(lessonId: "ru.1.1", targetCpm: 60, sessions: [failedCheck], storedStars: 2,
                                isPassed: true).stars == 1)
    #expect(LessonOverview.make(lessonId: "ru.1.1", targetCpm: 60, sessions: [failedCheck], storedStars: 2,
                                isPassed: false).stars == 0)
    #expect(LessonOverview.make(lessonId: "ru.1.1", targetCpm: 60, sessions: [], storedStars: 3, isPassed: true).stars == 4)
}

/// Половина пробела для подсказки — только когда ожидается пробел.
@MainActor @Test func spaceHalfOnlyForSpaceKey() {
    #expect(KeyboardView.spaceHalf(for: nil) == nil)
    #expect(KeyboardView.spaceHalf(for: KeyHighlight(keyCode: KeyboardGeometry.space, shiftKeyCode: nil, isError: false,
                                                      spaceThumb: .left)) == .left)
    #expect(KeyboardView.spaceHalf(for: KeyHighlight(keyCode: KeyboardGeometry.space, shiftKeyCode: nil, isError: true,
                                                      spaceThumb: .right)) == .right)
    #expect(KeyboardView.spaceHalf(for: KeyHighlight(keyCode: KeyboardGeometry.space, shiftKeyCode: nil,
                                                      isError: false)) == nil)
    // Другая клавиша: даже с рукой пробел не подсвечивается половиной.
    #expect(KeyboardView.spaceHalf(for: KeyHighlight(keyCode: 3, shiftKeyCode: nil, isError: false,
                                                      spaceThumb: .left)) == nil)
}

@Test func lessonRunKeepsOptionalSingleStep() {
    #expect(LessonRun(language: .ru, lessonId: "ru.1.1").onlyStep == nil)
    #expect(LessonRun(language: .ru, lessonId: "ru.1.1", onlyStep: .combos).onlyStep == .combos)
}

// MARK: - ★★★★★ — только за чистый урок

private func step(_ kind: ExerciseKind, accuracy: Double, errors: Int, cpm: Double = 100,
                  lessonId: String = "ru.1.1") -> SessionSummary {
    SessionSummary(day: "d", endedAt: .now, language: .ru, mode: .course, chars: 120, activeSeconds: 60,
                   accuracy: accuracy, completed: true, lessonId: lessonId, exerciseKind: kind, cpm: cpm,
                   errorCount: errors)
}

/// Урок «П и Р» пользователя: проверка на пятёрку, «Слова» 93,4% (8 ошибок) — на карте ★★★★;
/// после чистой попытки «Слова» — ★★★★★.
@Test func mapShowsFourStarsUntilEveryStepIsClean() {
    let dirty = [step(.drill, accuracy: 1, errors: 0), step(.combos, accuracy: 0.99, errors: 1),
                 step(.words, accuracy: 0.934, errors: 8), step(.check, accuracy: 1, errors: 0)]
    #expect(LessonOverview.make(lessonId: "ru.1.1", targetCpm: 60, sessions: dirty, storedStars: 3, isPassed: true).stars == 4)
    let cleaned = dirty + [step(.words, accuracy: 0.99, errors: 1)]
    #expect(LessonOverview.make(lessonId: "ru.1.1", targetCpm: 60, sessions: cleaned, storedStars: 3, isPassed: true).stars == 5)
}

/// «Прогресс курсов» в аналитике считает звёзды по тому же правилу, что карта курса.
@Test func analyticsCourseProgressAgreesWithTheMapOnCleanLesson() throws {
    let course = try CourseCatalog.load(.ru)
    let lesson = course.lessons[0], target = course.stages[0].targetCpm
    let sessions = [step(.words, accuracy: 0.934, errors: 8, lessonId: lesson.id),
                    step(.check, accuracy: 1, errors: 0, cpm: Double(target) * 2, lessonId: lesson.id)]
    let row = CourseProgressRow.make(course: course,
                                     lessons: [StoredLesson(lessonId: lesson.id, passed: true, storedStars: 3)],
                                     sessions: sessions)
    #expect(row.stars == 4)
    #expect(row.stars == LessonOverview.make(lessonId: lesson.id, targetCpm: target, sessions: sessions,
                                              storedStars: 3, isPassed: true).stars)
}

@Test func starsGainedOnlyWhenLessonStarsIncrease() {
    #expect(LessonOverview.starsGained(before: 4, after: 5) == 5)
    #expect(LessonOverview.starsGained(before: 5, after: 5) == nil)
    #expect(LessonOverview.starsGained(before: 4, after: 4) == nil)
    #expect(LessonOverview.starsGained(before: 5, after: 4) == nil)
}

/// Чистый повтор нечекового шага возвращает пятую: звёзды урока по истории до и после — 4 и 5.
@Test func cleanStepRepeatRegainsTheFifthStar() {
    func summary(_ kind: ExerciseKind, accuracy: Double, cpm: Double) -> SessionSummary {
        SessionSummary(day: "d", endedAt: .now, language: .ru, mode: .course, chars: 100, activeSeconds: 60,
                       accuracy: accuracy, completed: true, lessonId: "ru.1.1", exerciseKind: kind, cpm: cpm)
    }
    let check = summary(.check, accuracy: 1.0, cpm: 90)
    let messy = summary(.drill, accuracy: 0.9, cpm: 80)
    let clean = summary(.drill, accuracy: 1.0, cpm: 80)
    func stars(_ sessions: [SessionSummary]) -> Int {
        LessonOverview.make(lessonId: "ru.1.1", targetCpm: 60, sessions: sessions, storedStars: 0, isPassed: true).stars
    }
    let before = stars([check, messy]), after = stars([check, messy, clean])
    #expect(before == 4 && after == 5)
    #expect(LessonOverview.starsGained(before: before, after: after) == 5)
}
