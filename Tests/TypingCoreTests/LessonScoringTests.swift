import Testing
@testable import TypingCore

// «Действующая» оценка урока: единственное место, где складываются история проверок, зачёт и сохранённые звёзды.

@Test func effectiveStarsRecomputesFromHistoryByCurrentRule() {
    // 60 зн/мин — цель; 80 при 99,6% — четыре звезды (60 × 1,3 = 78)
    let history = [(cpm: 50.0, accuracy: 0.97), (cpm: 80.0, accuracy: 0.996)]
    #expect(LessonScoring.effectiveStars(history: history, steps: [], targetCpm: 60, passed: true, storedStars: 1) == 4)
    // история важнее базы: в базе 3, а по правилу лучшая проверка даёт 1
    #expect(LessonScoring.effectiveStars(history: [(cpm: 10, accuracy: 0.97)], steps: [], targetCpm: 60, passed: true,
                                         storedStars: 3) == 1)
}

/// Без истории хранимые звёзды (прежняя 3-звёздная шкала) переводятся в новую: 2 → ★★★.
@Test func effectiveStarsFallsBackToStoredWhenNoHistory() {
    #expect(LessonScoring.effectiveStars(history: [], steps: [], targetCpm: 60, passed: true, storedStars: 2) == 3)
    #expect(LessonScoring.effectiveStars(history: [], steps: [], targetCpm: 60, passed: false, storedStars: 2) == 3)
    #expect(LessonScoring.effectiveStars(history: [], steps: [], targetCpm: 60, passed: false, storedStars: 0) == 0)
}

/// Уроки издания 2 хранят звёзды уже в 5-звёздной шкале: без истории они берутся как есть (§16, решение 2).
@Test func effectiveStarsReadsStoredScaleByEdition() {
    #expect(LessonScoring.effectiveStars(history: [], steps: [], targetCpm: 60, passed: true, storedStars: 5,
                                         storedScale: .fiveStar) == 5)
    #expect(LessonScoring.effectiveStars(history: [], steps: [], targetCpm: 60, passed: true, storedStars: 2,
                                         storedScale: .legacy) == 3)
    #expect(LessonScoring.effectiveStars(sessions: [], lessonId: "ru2.s1.01", targetCpm: 60, passed: true,
                                         storedStars: 4) == 4)
    #expect(LessonScoring.effectiveStars(sessions: [], lessonId: "ru.1.1", targetCpm: 60, passed: true,
                                         storedStars: 3) == 4)
}

@Test func effectiveStarsOfPassedLessonIsAtLeastOne() {
    #expect(LessonScoring.effectiveStars(history: [], steps: [], targetCpm: 60, passed: true, storedStars: 0) == 1)
    // неудачная проверка после прохождения не отменяет зачёта
    #expect(LessonScoring.effectiveStars(history: [(cpm: 500, accuracy: 0.5)], steps: [], targetCpm: 60, passed: true,
                                         storedStars: 2) == 1)
    // не засчитан — нулевая оценка остаётся нулевой
    #expect(LessonScoring.effectiveStars(history: [(cpm: 500, accuracy: 0.5)], steps: [], targetCpm: 60, passed: false,
                                         storedStars: 2) == 0)
}

@Test func effectiveStarsFromSessionsUsesOnlyCompletedChecksOfTheLesson() {
    func session(_ id: String, _ kind: ExerciseKind, cpm: Double, accuracy: Double, completed: Bool = true) -> SessionSummary {
        SessionSummary(day: "2026-09-21", endedAt: .distantPast, language: .ru, mode: .course, chars: 100,
                       activeSeconds: 60, accuracy: accuracy, completed: completed, lessonId: id,
                       exerciseKind: kind, cpm: cpm)
    }
    let sessions = [
        session("ru.1.1", .check, cpm: 80, accuracy: 0.996),                    // четыре звезды
        session("ru.1.2", .check, cpm: 80, accuracy: 0.996),                    // другой урок
        session("ru.1.1", .drill, cpm: 500, accuracy: 1),                       // не проверка
        session("ru.1.1", .check, cpm: 500, accuracy: 1, completed: false),     // не завершена
    ]
    #expect(LessonScoring.effectiveStars(sessions: sessions, lessonId: "ru.1.1", targetCpm: 60, passed: true,
                                         storedStars: 0) == 4)
    #expect(LessonScoring.effectiveStars(sessions: sessions, lessonId: "ru.1.3", targetCpm: 60, passed: true,
                                         storedStars: 2) == 3)
}

// Шкала пяти звёзд (спецификация фазы 6, §4).

@Test func fiveStarScaleFollowsSpecTable() {
    let t = 60
    #expect(LessonScoring.stars(cpm: 200, accuracy: 0.95, targetCpm: t) == 0)
    #expect(LessonScoring.stars(cpm: 10, accuracy: 0.96, targetCpm: t) == 1)
    #expect(LessonScoring.stars(cpm: 47.9, accuracy: 1, targetCpm: t) == 1)
    #expect(LessonScoring.stars(cpm: 48, accuracy: 0.969, targetCpm: t) == 1)
    #expect(LessonScoring.stars(cpm: 48, accuracy: 0.97, targetCpm: t) == 2)
    #expect(LessonScoring.stars(cpm: 500, accuracy: 0.97, targetCpm: t) == 2)   // быстро, но неточно
    #expect(LessonScoring.stars(cpm: 59.9, accuracy: 1, targetCpm: t) == 2)
    #expect(LessonScoring.stars(cpm: 60, accuracy: 0.98, targetCpm: t) == 3)
    #expect(LessonScoring.stars(cpm: 78, accuracy: 0.99, targetCpm: t) == 3)
    #expect(LessonScoring.stars(cpm: 78, accuracy: 0.995, targetCpm: t) == 4)
    #expect(LessonScoring.stars(cpm: 78, accuracy: 1 - 1.0 / 200, targetCpm: t) == 4)   // допуск
    #expect(LessonScoring.stars(cpm: 89.9, accuracy: 1, targetCpm: t) == 4)
    #expect(LessonScoring.stars(cpm: 90, accuracy: 0.999, targetCpm: t) == 4)
    #expect(LessonScoring.stars(cpm: 90, accuracy: 1, targetCpm: t) == 5)
}

/// Новая шкала содержит прежнюю: прежние ★★ → не меньше ★★★, прежние ★★★ → не меньше ★★★★, прежняя ★ → ★ или ★★.
@Test func fiveStarScaleContainsOldScale() {
    func old(_ cpm: Double, _ accuracy: Double) -> Int {
        guard accuracy >= 0.96 else { return 0 }
        if cpm >= 78 && accuracy >= 0.995 { return 3 }
        if cpm >= 60 && accuracy >= 0.98 { return 2 }
        return 1
    }
    for cpm in stride(from: 20.0, through: 140, by: 1) {
        for accuracy in [0.95, 0.96, 0.965, 0.97, 0.975, 0.98, 0.99, 0.995, 0.999, 1] {
            let new = LessonScoring.stars(cpm: cpm, accuracy: accuracy, targetCpm: 60)
            switch old(cpm, accuracy) {
            case 0: #expect(new == 0)
            case 1: #expect((1...2).contains(new), "cpm \(cpm), \(accuracy)")
            case 2: #expect(new == 3, "cpm \(cpm), \(accuracy)")
            default: #expect(new >= 4, "cpm \(cpm), \(accuracy)")
            }
            #expect(LessonScoring.legacyScale(fiveStar: new) == old(cpm, accuracy), "cpm \(cpm), \(accuracy)")
        }
    }
}

@Test func scaleConversionsMatchSpec() {
    #expect((0...3).map { LessonScoring.fiveStarScale(legacy: $0) } == [0, 1, 3, 4])
    #expect((0...5).map { LessonScoring.legacyScale(fiveStar: $0) } == [0, 1, 1, 2, 3, 3])
}

@Test func allowedErrorsFollowSpecFormula() {
    #expect(LessonScoring.allowedErrors(chars: 100, accuracy: 0.97) == 3)
    #expect(LessonScoring.allowedErrors(chars: 100, accuracy: 0.98) == 2)
    #expect(LessonScoring.allowedErrors(chars: 120, accuracy: 0.995) == 0)   // ★★★★ на короткой проверке — 0
    #expect(LessonScoring.allowedErrors(chars: 300, accuracy: 0.995) == 1)
    #expect(LessonScoring.allowedErrors(chars: 300, accuracy: 1) == 0)
    #expect(LessonScoring.allowedErrors(chars: 0, accuracy: 0.96) == 0)
}

@Test func nextStarHintNamesSpeedAndErrors() throws {
    // ★★ → ★★★: не хватает скорости.
    #expect(LessonScoring.nextStarHint(cpm: 52, accuracy: 0.99, errors: 1, chars: 100, targetCpm: 60, steps: [])
        == NextStarHint(stars: 3, needCpm: 60, maxErrors: nil))
    // ★★ → ★★★: не хватает точности — не больше 2 ошибок.
    #expect(LessonScoring.nextStarHint(cpm: 120, accuracy: 0.97, errors: 3, chars: 100, targetCpm: 60, steps: [])
        == NextStarHint(stars: 3, needCpm: nil, maxErrors: 2))
    // ★ → ★★: обоих.
    #expect(LessonScoring.nextStarHint(cpm: 40, accuracy: 0.96, errors: 4, chars: 100, targetCpm: 60, steps: [])
        == NextStarHint(stars: 2, needCpm: 48, maxErrors: 3))
    // ★★★ → ★★★★: на 100 знаках — без ошибок.
    #expect(LessonScoring.nextStarHint(cpm: 80, accuracy: 0.99, errors: 1, chars: 100, targetCpm: 60, steps: [])
        == NextStarHint(stars: 4, needCpm: nil, maxErrors: 0))
    // ★★★★ → ★★★★★: только скорость.
    #expect(LessonScoring.nextStarHint(cpm: 80, accuracy: 1, errors: 0, chars: 100, targetCpm: 60, steps: [])
        == NextStarHint(stars: 5, needCpm: 90, maxErrors: nil))
    #expect(LessonScoring.nextStarHint(cpm: 95, accuracy: 1, errors: 0, chars: 100, targetCpm: 60, steps: []) == nil)
    #expect(LessonScoring.nextStarHint(cpm: 200, accuracy: 0.95, errors: 5, chars: 100, targetCpm: 60, steps: []) == nil)
}

/// Выполнив подсказку, получаем не меньше следующей звезды (93 зн/мин с одной ошибкой: подсказка «без ошибок»
/// к ★★★★ даёт сразу ★★★★★ — скорости уже хватает и для неё).
@Test func nextStarHintLeadsToNextStar() {
    for cpm in stride(from: 30.0, through: 120, by: 7) {
        for errors in 0...4 {
            let accuracy = 1 - Double(errors) / 100
            let stars = LessonScoring.stars(cpm: cpm, accuracy: accuracy, targetCpm: 60)
            guard let hint = LessonScoring.nextStarHint(cpm: cpm, accuracy: accuracy, errors: errors, chars: 100,
                                                        targetCpm: 60, steps: []) else {
                #expect(stars == 0 || stars == 5, "cpm \(cpm), errors \(errors)")
                continue
            }
            #expect(hint.stars == stars + 1)
            let fixedErrors = hint.maxErrors ?? errors
            let improved = LessonScoring.stars(cpm: hint.needCpm ?? cpm, accuracy: 1 - Double(fixedErrors) / 100,
                                               targetCpm: 60)
            #expect(improved >= stars + 1, "cpm \(cpm), errors \(errors)")
        }
    }
}

// ★★★★★ — только за чистый урок (решение пользователя 2026-10-25, §15.14): проверка на пятёрку и у каждого шага
// кроме проверки лучшая попытка не больше 2 ошибок на 100 знаков.

private func stat(_ kind: ExerciseKind, accuracy: Double, errors: Int = 0, index: Int? = nil) -> StepStat {
    StepStat(kind: kind, bestAccuracy: accuracy, errorsInBest: errors, cpmInBest: 80, bestCpm: 80, stepIndex: index)
}

private func summary(_ kind: ExerciseKind, lessonId: String = "ru.1.5", accuracy: Double, errors: Int,
                     cpm: Double = 100, completed: Bool = true) -> SessionSummary {
    SessionSummary(day: "2026-10-25", endedAt: .distantPast, language: .ru, mode: .course, chars: 120,
                   activeSeconds: 60, accuracy: accuracy, completed: completed, lessonId: lessonId,
                   exerciseKind: kind, cpm: cpm, errorCount: errors)
}

@Test func cleanLessonStepAccuracyIsTwoErrorsPerHundred() {
    #expect(LessonScoring.cleanLessonStepAccuracy == 0.98)
    #expect(LessonScoring.allowedErrors(chars: 100, accuracy: LessonScoring.cleanLessonStepAccuracy) == 2)
}

@Test func uncleanStepsAreNonCheckStepsBelowThreshold() {
    let steps = [stat(.drill, accuracy: 1), stat(.combos, accuracy: 0.98), stat(.words, accuracy: 0.934, errors: 8),
                 stat(.check, accuracy: 0.5, errors: 60)]   // проверка в расчёт не идёт
    #expect(LessonScoring.uncleanSteps(steps) == [steps[2]])
    #expect(LessonScoring.uncleanSteps([]).isEmpty)
    // Ровно на пороге (допуск): 1 − 2/100 в двоичной арифметике.
    #expect(LessonScoring.uncleanSteps([stat(.words, accuracy: 1 - 2.0 / 100)]).isEmpty)
    #expect(LessonScoring.uncleanSteps([stat(.words, accuracy: 0.979)]).map(\.kind) == [.words])
}

/// Проверка на пятёрку, «Слова» 93,4% (8 ошибок) → ★★★★; после чистой попытки «Слова» — ★★★★★.
@Test func fiveStarsNeedEveryStepClean() {
    let check = summary(.check, accuracy: 1, errors: 0, cpm: 100)
    let dirty = [summary(.drill, accuracy: 1, errors: 0), summary(.combos, accuracy: 0.99, errors: 1),
                 summary(.words, accuracy: 0.934, errors: 8), check]
    func stars(_ sessions: [SessionSummary]) -> Int {
        LessonScoring.effectiveStars(sessions: sessions, lessonId: "ru.1.5", targetCpm: 60, passed: true,
                                     storedStars: 3)
    }
    #expect(stars(dirty) == 4)
    #expect(stars(dirty + [summary(.words, accuracy: 0.98, errors: 2, cpm: 70)]) == 5)
    // Чистая попытка и худшая после неё: лучшая попытка шага остаётся лучшей.
    #expect(stars(dirty + [summary(.words, accuracy: 1, errors: 0), summary(.words, accuracy: 0.9, errors: 12)]) == 5)
    // Брошенная чистая попытка не считается.
    #expect(stars(dirty + [summary(.words, accuracy: 1, errors: 0, completed: false)]) == 4)
}

@Test func uncleanStepOnlyCapsTheFifthStar() {
    let dirty = [stat(.words, accuracy: 0.9, errors: 12)]
    // Ниже пятой звезды шаги не влияют.
    #expect(LessonScoring.lessonStars(checkStars: 4, steps: dirty) == 4)
    #expect(LessonScoring.lessonStars(checkStars: 3, steps: dirty) == 3)
    #expect(LessonScoring.lessonStars(checkStars: 1, steps: dirty) == 1)
    #expect(LessonScoring.lessonStars(checkStars: 0, steps: dirty) == 0)
    #expect(LessonScoring.lessonStars(checkStars: 5, steps: dirty) == 4)
    #expect(LessonScoring.lessonStars(checkStars: 5, steps: [stat(.words, accuracy: 1)]) == 5)
    // Через history-вариант то же самое.
    #expect(LessonScoring.effectiveStars(history: [(cpm: 100, accuracy: 1)], steps: dirty, targetCpm: 60,
                                         passed: true, storedStars: 0) == 4)
}

/// У шага нет завершённых попыток (старая история) — он не мешает.
@Test func stepWithoutAttemptsDoesNotBlock() {
    let check = summary(.check, accuracy: 1, errors: 0, cpm: 100)
    // Нет ни «Слов», ни «Сочетаний»; «Отработка» — брошена.
    let sessions = [summary(.drill, accuracy: 0.5, errors: 60, completed: false), check]
    #expect(LessonScoring.effectiveStars(sessions: sessions, lessonId: "ru.1.5", targetCpm: 60, passed: true,
                                         storedStars: 3) == 5)
    #expect(LessonScoring.effectiveStars(sessions: [check], lessonId: "ru.1.5", targetCpm: 60, passed: true,
                                         storedStars: 3) == 5)
}

/// Шаги другого урока не мешают.
@Test func stepsOfOtherLessonsAreIgnored() {
    let sessions = [summary(.check, accuracy: 1, errors: 0, cpm: 100),
                    summary(.words, lessonId: "ru.1.6", accuracy: 0.8, errors: 24)]
    #expect(LessonScoring.effectiveStars(sessions: sessions, lessonId: "ru.1.5", targetCpm: 60, passed: true,
                                         storedStars: 0) == 5)
}

@Test func nextStarHintNamesTheStepBlockingFifthStar() {
    let dirty = [stat(.drill, accuracy: 1), stat(.words, accuracy: 0.934, errors: 8)]
    // Проверка уже на ★★★★★, мешает шаг «Слова».
    #expect(LessonScoring.nextStarHint(cpm: 100, accuracy: 1, errors: 0, chars: 120, targetCpm: 60, steps: dirty)
        == NextStarHint(stars: 5, needCpm: nil, maxErrors: nil, blockingStep: dirty[1]))
    // Все шаги чистые — подсказки нет.
    #expect(LessonScoring.nextStarHint(cpm: 100, accuracy: 1, errors: 0, chars: 120, targetCpm: 60,
                                       steps: [stat(.words, accuracy: 1)]) == nil)
    // До пятой звезды не хватает и скорости: подсказка называет и её, и шаг.
    #expect(LessonScoring.nextStarHint(cpm: 80, accuracy: 1, errors: 0, chars: 120, targetCpm: 60, steps: dirty)
        == NextStarHint(stars: 5, needCpm: 90, maxErrors: nil, blockingStep: dirty[1]))
    // Ниже четвёртой звезды шаг в подсказку не попадает.
    #expect(LessonScoring.nextStarHint(cpm: 80, accuracy: 0.99, errors: 1, chars: 100, targetCpm: 60, steps: dirty)
        == NextStarHint(stars: 4, needCpm: nil, maxErrors: 0))
    // Проверка не засчитана — подсказки нет.
    #expect(LessonScoring.nextStarHint(cpm: 100, accuracy: 0.9, errors: 12, chars: 120, targetCpm: 60, steps: dirty) == nil)
    // Первый из нескольких мешающих шагов — в порядке урока.
    #expect(LessonScoring.nextStarHint(cpm: 100, accuracy: 1, errors: 0, chars: 120, targetCpm: 60,
                                       steps: [stat(.combos, accuracy: 0.9), stat(.words, accuracy: 0.9)])?.blockingStep?.kind
        == .combos)
}

/// Шаги издания 2 повторяются по виду: мешающий шаг называется номером (решение 22).
@Test func uncleanStepsKeepStepIndex() {
    let steps = [stat(.words, accuracy: 1, index: 2), stat(.words, accuracy: 0.9, errors: 12, index: 3),
                 stat(.check, accuracy: 1, index: 5)]
    #expect(LessonScoring.uncleanSteps(steps).map(\.stepIndex) == [3])
    let hint = LessonScoring.nextStarHint(cpm: 100, accuracy: 1, errors: 0, chars: 120, targetCpm: 60, steps: steps)
    #expect(hint?.stars == 5 && hint?.blockingStep?.stepIndex == 3)
}
