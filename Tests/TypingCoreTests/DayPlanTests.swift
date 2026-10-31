import Foundation
import Testing
@testable import TypingCore

// План на сегодня: состав, размер и выполнение (§10.1; решения 12–14).

/// Номера логических дней: 20 100 — чётный, mod 3 = 0; 20 101 — нечётный, 1; 20 102 — чётный, 2; 20 103 — нечётный, 0.
private func day(_ number: Int) -> String { RefreshSchedule.dayKey(number) }

private func lesson(_ index: Int = 0) throws -> Lesson { try CourseCatalog.load(.ru).lessons[index] }

private func input(today: Int = 20_100, goal: Int = 10, median: Double? = 120, target: ContinueTarget? = nil,
                   completed: Bool = false, review: String? = "ru2.review", speedup: String? = "ru2.speedup",
                   due: [String] = [], rotation: String? = nil, focus: [Character] = ["а", "о", "в"],
                   weak: Finger? = .leftRing, strong: Finger? = .rightIndex, stage: Int? = 4,
                   sessions: [SessionSummary] = [], steps: [String: Int] = [:]) -> DayPlanInput {
    DayPlanInput(today: day(today), goalMinutes: goal, medianCpm: median, continueTarget: target,
                 courseCompleted: completed, lastReviewId: review, lastSpeedupId: speedup, dueRefreshes: due,
                 rotationLesson: rotation, reviewFocus: focus, weakFinger: weak, strongFinger: strong,
                 textStageIndex: stage, todaySessions: sessions, lessonStepCounts: steps)
}

private func session(day key: String, slot: PlanSlot? = nil, mode: ExerciseMode = .practice,
                     kind: ExerciseKind? = nil, completed: Bool = true, lessonId: String = "ru2.s1.01",
                     step: Int? = nil) -> SessionSummary {
    SessionSummary(day: key, endedAt: Date(timeIntervalSince1970: 0), language: .ru, mode: mode, chars: 100,
                   activeSeconds: 60, accuracy: 1, completed: completed, lessonId: kind == nil ? nil : lessonId,
                   exerciseKind: kind, stepIndex: step, planSlot: slot)
}

private func action(_ plan: DayPlan, _ slot: PlanSlot) -> PlanAction? { plan.items.first { $0.slot == slot }?.action }

// MARK: - Состав

@Test func planHasFourItemsInSlotOrder() {
    let plan = DayPlanner.make(input())
    #expect(plan.items.map(\.slot) == [.warmup, .lesson, .training, .text])
    #expect(plan.day == day(20_100))
}

@Test func warmupTakesFirstDueRefreshAndKeepsSecond() {
    let plan = DayPlanner.make(input(due: ["ru2.s1.03", "ru2.s1.01", "ru2.s2.02"], rotation: "ru2.s1.05"))
    #expect(action(plan, .warmup) == .refresh(lessonId: "ru2.s1.03"))
    #expect(plan.extraRefresh == "ru2.s1.01")
    let single = DayPlanner.make(input(due: ["ru2.s1.03"]))
    #expect(single.extraRefresh == nil)
    // Второй возврат освежён сегодня — строки «Ещё» больше нет; освежён вчера или брошен — строка остаётся.
    let due = ["ru2.s1.03", "ru2.s1.01"]
    let refreshed = session(day: day(20_100), mode: .course, kind: .refresh, lessonId: "ru2.s1.01")
    #expect(DayPlanner.make(input(due: due, sessions: [refreshed])).extraRefresh == nil)
    let yesterday = session(day: day(20_099), mode: .course, kind: .refresh, lessonId: "ru2.s1.01")
    #expect(DayPlanner.make(input(due: due, sessions: [yesterday])).extraRefresh == "ru2.s1.01")
    let abandoned = session(day: day(20_100), mode: .course, kind: .refresh, completed: false, lessonId: "ru2.s1.01")
    #expect(DayPlanner.make(input(due: due, sessions: [abandoned])).extraRefresh == "ru2.s1.01")
}

@Test func warmupWithoutDueRotatesOnEvenDays() {
    #expect(action(DayPlanner.make(input(today: 20_100, rotation: "ru2.s1.05")), .warmup)
            == .refresh(lessonId: "ru2.s1.05"))
    #expect(DayPlanner.make(input(today: 20_100, rotation: "ru2.s1.05")).extraRefresh == nil)
    // Нечётный день — «Повтор», даже если кандидат есть; чётный без кандидата — тоже «Повтор».
    #expect(action(DayPlanner.make(input(today: 20_101, rotation: "ru2.s1.05")), .warmup)
            == .review(focus: ["а", "о", "в"], chars: 200))
    #expect(action(DayPlanner.make(input(today: 20_100)), .warmup) == .review(focus: ["а", "о", "в"], chars: 200))
}

@Test func reviewSizeFollowsGoalAndMedianSpeed() {
    func chars(goal: Int, median: Double?) -> Int? {
        guard case let .review(_, chars) = action(DayPlanner.make(input(today: 20_101, goal: goal, median: median)),
                                                   .warmup) else { return nil }
        return chars
    }
    #expect(chars(goal: 10, median: 120) == 200)
    #expect(chars(goal: 30, median: 150) == 600)
    #expect(chars(goal: 15, median: 90) == 300)    // share 10/3 · 90
    #expect(chars(goal: 3, median: 200) == 200)    // share 0 → нижняя граница
    #expect(chars(goal: 17, median: nil) == 400)   // C = 100 без данных
}

@Test func lessonFollowsContinueTarget() throws {
    let next = try lesson(2), check = try lesson(5)
    #expect(action(DayPlanner.make(input(target: .lesson(next))), .lesson)
            == .lesson(lessonId: next.id, retake: false))
    #expect(action(DayPlanner.make(input(target: .retakeCheck(check))), .lesson)
            == .lesson(lessonId: check.id, retake: true))
}

@Test func completedCourseAlternatesReviewAndSpeedup() {
    #expect(action(DayPlanner.make(input(today: 20_100, completed: true)), .lesson)
            == .lesson(lessonId: "ru2.review", retake: false))
    #expect(action(DayPlanner.make(input(today: 20_101, completed: true)), .lesson)
            == .lesson(lessonId: "ru2.speedup", retake: false))
}

@Test func trainingRotatesByDayNumber() {
    #expect(action(DayPlanner.make(input(today: 20_100)), .training) == .finger(.leftRing, .accuracy, portions: 1))
    #expect(action(DayPlanner.make(input(today: 20_101)), .training) == .finger(.rightIndex, .speed, portions: 1))
    #expect(action(DayPlanner.make(input(today: 20_102)), .training) == .adaptive(portions: 1))
    #expect(action(DayPlanner.make(input(today: 20_103)), .training) == .finger(.leftRing, .accuracy, portions: 1))
}

@Test func trainingFallsToNextInCircle() {
    // Нет слабого — «Скорость пальца»; нет сильного — адаптивный; ни одного пальца — адаптивный.
    #expect(action(DayPlanner.make(input(today: 20_100, weak: nil)), .training)
            == .finger(.rightIndex, .speed, portions: 1))
    #expect(action(DayPlanner.make(input(today: 20_101, strong: nil)), .training) == .adaptive(portions: 1))
    #expect(action(DayPlanner.make(input(today: 20_100, weak: nil, strong: nil)), .training)
            == .adaptive(portions: 1))
}

@Test func trainingPortionsFollowGoal() {
    // share = (G − 5) / 3; порций — max(1, round(share / 3)).
    #expect(action(DayPlanner.make(input(today: 20_102, goal: 20)), .training) == .adaptive(portions: 2))
    #expect(action(DayPlanner.make(input(today: 20_102, goal: 30)), .training) == .adaptive(portions: 3))
    #expect(action(DayPlanner.make(input(today: 20_100, goal: 30)), .training)
            == .finger(.leftRing, .accuracy, portions: 3))
}

@Test func textPortionsOf450AndPhrasesBeforeStageFour() {
    #expect(action(DayPlanner.make(input(goal: 10, median: 120, stage: 4)), .text)
            == .text(stageIndex: 4, portions: 1, chars: 450))
    #expect(action(DayPlanner.make(input(goal: 30, median: 150, stage: 3)), .text)
            == .text(stageIndex: 3, portions: 3, chars: 450))   // 1250 / 450 ≈ 2,8
    #expect(action(DayPlanner.make(input(stage: 2)), .text) == .text(stageIndex: nil, portions: 1, chars: 450))
    #expect(action(DayPlanner.make(input(stage: nil)), .text) == .text(stageIndex: nil, portions: 1, chars: 450))
}

@Test func samePlanForSameInput() throws {
    let source = input(today: 20_101, target: .lesson(try lesson(1)), due: ["ru2.s1.03"])
    #expect(DayPlanner.make(source) == DayPlanner.make(source))
}

// MARK: - Выполнение

@Test func completedSlotSessionMarksItemDone() {
    let today = day(20_100)
    let plan = DayPlanner.make(input(sessions: [session(day: today, slot: .warmup)]))
    #expect(plan.items.map(\.done) == [true, false, false, false])
    #expect(plan.next?.slot == .lesson)
    #expect(plan.doneCount == 1)
    #expect(!plan.isDone)
}

@Test func abandonedAndYesterdaySessionsDoNotCount() {
    let plan = DayPlanner.make(input(sessions: [session(day: day(20_100), slot: .warmup, completed: false),
                                                session(day: day(20_099), slot: .training)]))
    #expect(plan.doneCount == 0)
    #expect(plan.next?.slot == .warmup)
}

@Test func lessonCheckWithoutSlotCountsLesson() {
    let today = day(20_100)
    let check = DayPlanner.make(input(sessions: [session(day: today, mode: .course, kind: .check)]))
    #expect(check.items.map(\.done) == [false, true, false, false])
    let fromPlan = DayPlanner.make(input(sessions: [session(day: today, slot: .lesson, mode: .course, kind: .check)]))
    #expect(fromPlan.items.map(\.done) == [false, true, false, false])
    // «Освежить» без слота и брошенная проверка урок не засчитывают; другие шаги урока — тоже.
    let other = DayPlanner.make(input(sessions: [session(day: today, mode: .course, kind: .refresh),
                                                 session(day: today, mode: .course, kind: .check, completed: false),
                                                 session(day: today, mode: .course, kind: .words)]))
    #expect(other.doneCount == 0)
}

/// Урок без проверки засчитывает половина его шагов (с округлением вверх) за сегодня — с планом или с карты курса.
@Test func halfOfLessonStepsCountsLesson() throws {
    let today = day(20_100)
    let id = try lesson(1).id
    func done(_ sessions: [SessionSummary], steps: Int? = 7) throws -> Bool {
        let plan = DayPlanner.make(input(target: .lesson(try lesson(1)), sessions: sessions,
                                         steps: steps.map { [id: $0] } ?? [:]))
        return plan.items[1].done
    }
    func step(_ index: Int, slot: PlanSlot? = nil, day key: String? = nil, kind: ExerciseKind = .words,
              lessonId: String? = nil) -> SessionSummary {
        session(day: key ?? today, slot: slot, mode: .course, kind: kind, lessonId: lessonId ?? id, step: index)
    }
    // Один шаг из плана — ещё не урок.
    #expect(try !done([step(0, slot: .lesson)]))
    // 4 разных шага из 7 — урок засчитан, 3 — нет.
    #expect(try done([step(0, slot: .lesson), step(1), step(2), step(3)]))
    #expect(try !done([step(0), step(1), step(2)]))
    // Повтор того же шага считается один раз.
    #expect(try !done([step(0), step(1), step(2), step(2)]))
    // Вчерашние шаги, шаги другого урока, брошенные и «Освежить» не считаются.
    #expect(try !done([step(0), step(1), step(2), step(3, day: day(20_099))]))
    #expect(try !done([step(0), step(1), step(2), step(3, lessonId: "ru2.s9.09")]))
    #expect(try !done([step(0), step(1), step(2), step(3, kind: .refresh)]))
    var abandoned = [step(0), step(1), step(2)]
    abandoned.append(session(day: today, mode: .course, kind: .words, completed: false, lessonId: id, step: 3))
    #expect(try !done(abandoned))
    // Число шагов неизвестно — урок засчитывает только проверка.
    #expect(try !done([step(0), step(1), step(2), step(3)], steps: nil))
}

/// «Пересдать проверку»: половина шагов проверки пункт не засчитывает — только сама проверка.
@Test func retakeCountsOnlyByCheck() throws {
    let today = day(20_100)
    let check = try #require(CourseCatalog.load(.ru).lessons.first { $0.kind == .stageCheck })
    let steps = [check.id: 3]
    let partial = (0..<2).map { session(day: today, mode: .course, kind: .words, lessonId: check.id, step: $0) }
    #expect(!DayPlanner.make(input(target: .retakeCheck(check), sessions: partial, steps: steps)).items[1].done)
    let finished = partial + [session(day: today, mode: .course, kind: .check, lessonId: check.id, step: 2)]
    #expect(DayPlanner.make(input(target: .retakeCheck(check), sessions: finished, steps: steps)).items[1].done)
}

/// Курс пройден: «Повтор» засчитывает то же правило — проверка или половина его шагов.
@Test func completedCourseLessonCountsByHalfOfItsSteps() {
    let today = day(20_100)
    let steps = (0..<3).map { session(day: today, mode: .course, kind: .words, lessonId: "ru2.review", step: $0) }
    let plan = DayPlanner.make(input(completed: true, sessions: steps, steps: ["ru2.review": 6]))
    #expect(plan.items[1].action == .lesson(lessonId: "ru2.review", retake: false))
    #expect(plan.items[1].done)
}

@Test func planIsDoneWhenAllFourCounted() {
    let today = day(20_100)
    let plan = DayPlanner.make(input(sessions: [session(day: today, slot: .warmup),
                                                session(day: today, mode: .course, kind: .check),
                                                session(day: today, slot: .training),
                                                session(day: today, slot: .text)]))
    #expect(plan.isDone)
    #expect(plan.doneCount == 4)
    #expect(plan.next == nil)
}

@Test func planSlotTitlesAreTranslated() {
    #expect(PlanSlot.allCases.map(\.rawValue) == ["warmup", "lesson", "training", "text"])
    #expect(PlanSlot.allCases.map { CoreText.localized($0.titleKey, localization: "en") }
            == ["Warm-up", "Lesson", "Training", "Text"])
    #expect(PlanSlot.allCases.map { CoreText.localized($0.titleKey, localization: "ru") }
            == ["Разминка", "Урок", "Тренировка", "Текст"])
}
