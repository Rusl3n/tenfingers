import Foundation
import Testing
@testable import TypingCore

private func step(_ kind: ExerciseKind?, lessonId: String? = "ru.1.1", accuracy: Double, cpm: Double = 60,
                  errors: Int = 0, completed: Bool = true, mode: ExerciseMode = .course) -> SessionSummary {
    SessionSummary(day: "2026-10-24", endedAt: Date(timeIntervalSince1970: 0), language: .ru, mode: mode,
                   chars: 100, activeSeconds: 60, accuracy: accuracy, completed: completed,
                   lessonId: lessonId, exerciseKind: kind, cpm: cpm, errorCount: errors)
}

@Test func sessionSummaryDefaultsKeepOldCallsWorking() {
    let old = SessionSummary(day: "d", endedAt: .distantPast, language: .en, mode: .practice, chars: 300,
                             activeSeconds: 60, accuracy: 1, completed: true)
    #expect(old.lessonId == nil && old.exerciseKind == nil && old.errorCount == 0)
    #expect(old.speed == 300) // без сохранённой скорости — знаки за минуту
}

private func effective(_ history: [SessionSummary], passed: Bool = false, stored: Int = 0) -> Int {
    LessonScoring.effectiveStars(sessions: history, lessonId: "ru.1.1", targetCpm: 60, passed: passed,
                                 storedStars: stored)
}

@Test func starsFromHistoryTakeBestCheck() {
    // 100% при 1,5×цели — ★★★★★; 97% при 2×цели — ★★.
    let history = [
        step(.check, accuracy: 1.0, cpm: 90),
        step(.check, accuracy: 0.97, cpm: 120),
        step(.words, accuracy: 1.0, cpm: 500),                 // не проверочный шаг
        step(.check, lessonId: "ru.1.2", accuracy: 1, cpm: 500), // другой урок
    ]
    #expect(effective(history) == 5)
}

@Test func starsFromHistoryIgnoreAbandonedAndNeedCheck() {
    // Без подходящей проверки истории нет — берутся сохранённые звёзды (прежняя шкала: 2 → ★★★).
    #expect(effective([step(.check, accuracy: 1, cpm: 500, completed: false)], stored: 2) == 3)
    #expect(effective([step(.drill, accuracy: 1)], stored: 2) == 3)
    #expect(effective([step(.check, accuracy: 0.9)], stored: 2) == 0)
}

@Test func stepStatsTakeBestAttemptPerStepInLessonOrder() {
    let stats = LessonStepStats.summarize(sessions: [
        step(.words, accuracy: 0.95, cpm: 100, errors: 6),
        step(.drill, accuracy: 0.97, cpm: 50, errors: 3),
        step(.drill, accuracy: 1.0, cpm: 40, errors: 0),
        step(.drill, accuracy: 0.99, cpm: 70, errors: 1),
        step(.drill, accuracy: 1.0, cpm: 10, completed: false), // брошенная попытка не считается
        step(.check, lessonId: "ru.1.2", accuracy: 1),           // другой урок
        step(nil, accuracy: 1, mode: .practice),
    ], lessonId: "ru.1.1")
    #expect(stats.map(\.kind) == [.drill, .words])
    #expect(stats[0] == StepStat(kind: .drill, bestAccuracy: 1.0, errorsInBest: 0, cpmInBest: 40, bestCpm: 70))
    #expect(stats[1] == StepStat(kind: .words, bestAccuracy: 0.95, errorsInBest: 6, cpmInBest: 100, bestCpm: 100))
}

@Test func tieOnAccuracyPrefersFasterAttemptForErrors() {
    let stats = LessonStepStats.summarize(sessions: [
        step(.combos, accuracy: 0.98, cpm: 50, errors: 2),
        step(.combos, accuracy: 0.98, cpm: 80, errors: 1),
    ], lessonId: "ru.1.1")
    #expect(stats.first?.errorsInBest == 1)
}

@Test func totalErrorsSumBestAttempts() {
    let stats = [
        StepStat(kind: .drill, bestAccuracy: 1.0, errorsInBest: 0, cpmInBest: 60, bestCpm: 60),
        StepStat(kind: .words, bestAccuracy: 0.9, errorsInBest: 6, cpmInBest: 60, bestCpm: 60),
        StepStat(kind: .check, bestAccuracy: 0.98, errorsInBest: 1, cpmInBest: 60, bestCpm: 60),
    ]
    #expect(LessonStepStats.totalErrors(stats) == 7)
    #expect(LessonStepStats.totalErrors([]) == nil)
}

@Test func improvementComparesWithPreviousBest() {
    let best = StepStat(kind: .drill, bestAccuracy: 0.98, errorsInBest: 2, cpmInBest: 70, bestCpm: 70)
    #expect(LessonStepStats.isImprovement(accuracy: 0.99, cpm: 10, over: best))
    #expect(LessonStepStats.isImprovement(accuracy: 0.98, cpm: 80, over: best))
    #expect(!LessonStepStats.isImprovement(accuracy: 0.98, cpm: 70, over: best))
    #expect(!LessonStepStats.isImprovement(accuracy: 0.97, cpm: 200, over: best))
    #expect(LessonStepStats.isImprovement(accuracy: 0.5, cpm: 10, over: nil))
}

/// «Лучший результат!» сравнивается с лучшей попыткой целиком: её точностью и её же скоростью,
/// а не с самой высокой скоростью среди всех попыток.
@Test func improvementUsesBestAttemptsOwnSpeed() throws {
    let stats = LessonStepStats.summarize(sessions: [
        step(.drill, accuracy: 1.0, cpm: 50),
        step(.drill, accuracy: 0.9, cpm: 100),
    ], lessonId: "ru.1.1")
    let previous = try #require(stats.first)
    #expect(previous.cpmInBest == 50 && previous.bestCpm == 100)
    #expect(LessonStepStats.isImprovement(accuracy: 1.0, cpm: 60, over: previous))
    #expect(!LessonStepStats.isImprovement(accuracy: 1.0, cpm: 50, over: previous))
}

@Test func exerciseKindHasLocalizedTitle() {
    #expect(["Combinations", "Сочетания"].contains(ExerciseKind.combos.localizedTitle))
    for kind in ExerciseKind.allCases {
        #expect(CoreText.localized(kind.titleKey, localization: "en") != kind.titleKey, "\(kind)")
    }
    #expect(CoreText.localized("Разминка", localization: "en") == "Warm-up")
}

// MARK: - Шаги по номеру (решение 22)

private func numbered(_ kind: ExerciseKind, _ index: Int?, accuracy: Double = 1, cpm: Double = 60,
                      errors: Int = 0) -> SessionSummary {
    SessionSummary(day: "2026-10-25", endedAt: Date(timeIntervalSince1970: 0), language: .ru, mode: .course,
                   chars: 100, activeSeconds: 60, accuracy: accuracy, completed: true, lessonId: "ru2.s1.01",
                   exerciseKind: kind, cpm: cpm, errorCount: errors, stepIndex: index)
}

@Test func stepsOfTheSameKindAreSeparatedByIndex() {
    let stats = LessonStepStats.summarize(sessions: [
        numbered(.words, 3, accuracy: 0.9, cpm: 70, errors: 10),
        numbered(.words, 2, accuracy: 0.95, cpm: 50, errors: 5),
        numbered(.words, 2, accuracy: 0.99, cpm: 40, errors: 1),
    ], lessonId: "ru2.s1.01")
    #expect(stats == [
        StepStat(kind: .words, bestAccuracy: 0.99, errorsInBest: 1, cpmInBest: 40, bestCpm: 50, stepIndex: 2),
        StepStat(kind: .words, bestAccuracy: 0.9, errorsInBest: 10, cpmInBest: 70, bestCpm: 70, stepIndex: 3),
    ])
}

@Test func unnumberedAttemptJoinsTheFirstNumberedStepOfItsKind() {
    let stats = LessonStepStats.summarize(sessions: [
        numbered(.words, 3, accuracy: 0.9),
        numbered(.words, 2, accuracy: 0.95),
        numbered(.words, nil, accuracy: 1, cpm: 90),
    ], lessonId: "ru2.s1.01")
    #expect(stats.map(\.stepIndex) == [2, 3])
    #expect(stats[0].bestAccuracy == 1 && stats[0].bestCpm == 90)
}

@Test func unnumberedAttemptWithoutPairKeepsTheOldKindOrder() {
    let stats = LessonStepStats.summarize(sessions: [
        numbered(.phrases, 4),
        numbered(.check, nil),       // ранг 3
        numbered(.drill, 0),
        numbered(.combos, nil),      // ранг 1: после шага 0, перед шагом 4
        numbered(.sentences, nil),   // ранг 100 + индекс в allCases: в конце
        numbered(.words, 1),
        numbered(.words, nil),       // сливается с шагом 1
    ], lessonId: "ru2.s1.01")
    #expect(stats.map(\.kind) == [.drill, .words, .combos, .check, .phrases, .sentences])
    #expect(stats.map(\.stepIndex) == [0, 1, nil, nil, 4, nil])
}

@Test func numberedStepComesBeforeUnnumberedOfTheSameRank() {
    // Шаг 1 (phrases) и запись без номера вида combos (ранг 1): при равенстве — с номером первой.
    let stats = LessonStepStats.summarize(sessions: [numbered(.combos, nil), numbered(.phrases, 1)],
                                          lessonId: "ru2.s1.01")
    #expect(stats.map(\.kind) == [.phrases, .combos])
}

@Test func refreshJoinsTheCheckRowAndTakesTheBetterOfTheTwo() {
    let stats = LessonStepStats.summarize(sessions: [
        numbered(.words, 0), numbered(.check, 1, accuracy: 0.96, cpm: 50, errors: 4),
        numbered(.refresh, 1, accuracy: 0.99, cpm: 60, errors: 1),
    ], lessonId: "ru2.s1.01")
    #expect(stats == [
        StepStat(kind: .words, bestAccuracy: 1, errorsInBest: 0, cpmInBest: 60, bestCpm: 60, stepIndex: 0),
        StepStat(kind: .check, bestAccuracy: 0.99, errorsInBest: 1, cpmInBest: 60, bestCpm: 60, stepIndex: 1),
    ])
    // «Освежить» без самой проверки и без номера — тоже строка проверки.
    #expect(LessonStepStats.summarize(sessions: [numbered(.refresh, nil)], lessonId: "ru2.s1.01").map(\.kind) == [.check])
}
