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

@Test func starsFromHistoryTakeBestCheck() {
    // 100% при 1,5×цели — ★★★; 97% при 2×цели — ★.
    let history = [
        step(.check, accuracy: 1.0, cpm: 90),
        step(.check, accuracy: 0.97, cpm: 120),
        step(.words, accuracy: 1.0, cpm: 500),                 // не проверочный шаг
        step(.check, lessonId: "ru.1.2", accuracy: 1, cpm: 500), // другой урок
    ]
    #expect(LessonScoring.bestStars(sessions: history, lessonId: "ru.1.1", targetCpm: 60) == 3)
}

@Test func starsFromHistoryIgnoreAbandonedAndNeedCheck() {
    #expect(LessonScoring.bestStars(sessions: [step(.check, accuracy: 1, cpm: 500, completed: false)],
                                    lessonId: "ru.1.1", targetCpm: 60) == nil)
    #expect(LessonScoring.bestStars(sessions: [step(.drill, accuracy: 1)], lessonId: "ru.1.1", targetCpm: 60) == nil)
    #expect(LessonScoring.bestStars(sessions: [step(.check, accuracy: 0.9)], lessonId: "ru.1.1", targetCpm: 60) == 0)
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

@Test func averageAccuracyIsMeanOfBestPerStep() {
    let stats = [
        StepStat(kind: .drill, bestAccuracy: 1.0, errorsInBest: 0, cpmInBest: 60, bestCpm: 60),
        StepStat(kind: .check, bestAccuracy: 0.946, errorsInBest: 5, cpmInBest: 60, bestCpm: 60),
    ]
    #expect(abs((LessonStepStats.averageAccuracy(stats) ?? 0) - 0.973) < 1e-9)
    #expect(LessonStepStats.averageAccuracy([]) == nil)
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
}
