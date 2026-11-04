import Testing
@testable import TypingCore

private let goal = 600.0
private func full() -> DayActivity { DayActivity(activeSeconds: 700, completedExercises: 3) }
private func half() -> DayActivity { DayActivity(activeSeconds: 60, completedExercises: 1) }
private func days(_ list: [(String, DayActivity)]) -> [String: DayActivity] { Dictionary(uniqueKeysWithValues: list) }
private func oct(_ day: Int) -> String { day < 10 ? "2026-10-0\(day)" : "2026-10-\(day)" }

@Test func emptyHistory() {
    let s = StreakCalculator.summarize(days: [:], today: "2026-10-24", goalSeconds: goal)
    #expect(s.current == 0 && s.freezes == 0 && s.today == .none)
}

@Test func statusRules() {
    #expect(StreakCalculator.status(full(), goalSeconds: goal) == .full)
    #expect(StreakCalculator.status(half(), goalSeconds: goal) == .half)
    #expect(StreakCalculator.status(DayActivity(activeSeconds: 900, completedExercises: 0), goalSeconds: goal) == .none)
    #expect(StreakCalculator.status(nil, goalSeconds: goal) == .none)
}

@Test func halfAndFullBothExtendStreak() {
    let s = StreakCalculator.summarize(days: days([("2026-10-20", full()), ("2026-10-21", half()), ("2026-10-22", full())]),
                                       today: "2026-10-22", goalSeconds: goal)
    #expect(s.current == 3)
    #expect(s.fullInCurrent == 2)
    #expect(s.fullInRow == 1)
    #expect(s.today == .full)
}

@Test func todayWithoutPracticeDoesNotBreakStreak() {
    let s = StreakCalculator.summarize(days: days([("2026-10-22", full()), ("2026-10-23", full())]),
                                       today: "2026-10-24", goalSeconds: goal)
    #expect(s.current == 2)
    #expect(s.today == .none)
}

@Test func missedDayWithoutFreezeResets() {
    // 23-е (сегодня) ещё без занятий: пропущенный 21-й не спасён двойной целью 22-го (22-го набрана одна цель).
    let s = StreakCalculator.summarize(days: days([("2026-10-20", full()), ("2026-10-22", full())]),
                                       today: "2026-10-23", goalSeconds: goal)
    #expect(s.current == 1)
    #expect(s.statuses["2026-10-21"] == DayStatus.none)
    #expect(s.longest == 1)
}

@Test func sevenFullDaysEarnAFreezeWhichCoversAMiss() {
    var list: [(String, DayActivity)] = []
    for d in 1...7 { list.append((oct(d), full())) }
    list.append(("2026-10-09", full()))   // 8-е пропущено
    let s = StreakCalculator.summarize(days: days(list), today: "2026-10-09", goalSeconds: goal)
    #expect(s.statuses["2026-10-08"] == .frozen)
    #expect(s.current == 9)
    #expect(s.freezes == 0)
    #expect(s.fullInRow == 1)
}

@Test func freezesCapAtTwo() {
    var list: [(String, DayActivity)] = []
    for d in 1...21 { list.append((oct(d), full())) }
    let s = StreakCalculator.summarize(days: days(list), today: "2026-10-21", goalSeconds: goal)
    #expect(s.freezes == 2)
}

@Test func halfDayResetsFullCounter() {
    var list: [(String, DayActivity)] = []
    for d in 1...6 { list.append((oct(d), full())) }
    list.append(("2026-10-07", half()))
    for d in 8...13 { list.append((oct(d), full())) }
    let s = StreakCalculator.summarize(days: days(list), today: "2026-10-13", goalSeconds: goal)
    #expect(s.freezes == 0)
    #expect(s.current == 13)
    #expect(s.fullInRow == 6)
    #expect(s.fullInCurrent == 12)
}

@Test func moreMissesThanFreezesResets() {
    var list: [(String, DayActivity)] = []
    for d in 1...7 { list.append((oct(d), full())) }
    list.append(("2026-10-11", full()))   // 8, 9, 10 пропущены, заморозка одна
    let s = StreakCalculator.summarize(days: days(list), today: "2026-10-11", goalSeconds: goal)
    #expect(s.statuses["2026-10-08"] == .frozen)
    #expect(s.statuses["2026-10-09"] == DayStatus.none)
    #expect(s.current == 1)
    #expect(s.longest == 8)
}

@Test func dayKeysCrossMonthAndYear() {
    #expect(StreakCalculator.dayKeys(from: "2026-12-30", to: "2027-01-02") ==
            ["2026-12-30", "2026-12-31", "2027-01-01", "2027-01-02"])
    #expect(StreakCalculator.dayKeys(from: "2026-03-28", to: "2026-03-30").count == 3)
}

// MARK: - Пограничные случаи

@Test func missedYesterdayWithoutFreezeAndNothingTodayResets() {
    // 4-го и 5-го пропуск, 6-го (сегодня) ещё не занимались: спасать нечего — следующий день после пропуска пуст.
    let list = (1...3).map { (oct($0), full()) }
    let s = StreakCalculator.summarize(days: days(list), today: oct(6), goalSeconds: goal)
    #expect(s.current == 0)
    #expect(s.fullInCurrent == 0 && s.fullInRow == 0)
    #expect(s.statuses[oct(4)] == DayStatus.none)
    #expect(s.today == DayStatus.none)
    #expect(s.longest == 3)
}

@Test func missedYesterdayWithFreezeAndNothingTodayKeepsStreak() {
    let list = (1...7).map { (oct($0), full()) }   // заморозка за 7 полных; 8-го пропуск, 9-го (сегодня) пусто
    let s = StreakCalculator.summarize(days: days(list), today: oct(9), goalSeconds: goal)
    #expect(s.statuses[oct(8)] == .frozen)
    #expect(s.current == 8)
    #expect(s.freezes == 0)
    #expect(s.fullInRow == 0)
    #expect(s.fullInCurrent == 7)
    #expect(s.today == DayStatus.none)
    #expect(s.statuses[oct(9)] == DayStatus.none)
}

@Test func futureKeysAreIgnored() {
    let list = [(oct(1), full()), (oct(2), half()), (oct(20), full())]
    let s = StreakCalculator.summarize(days: days(list), today: oct(2), goalSeconds: goal)
    #expect(s.current == 2)
    #expect(s.statuses[oct(20)] == nil)
    #expect(s.statuses.keys.sorted() == [oct(1), oct(2)])
    // Только будущие дни — как пустая история.
    let future = StreakCalculator.summarize(days: days([(oct(20), full())]), today: oct(2), goalSeconds: goal)
    #expect(future.current == 0 && future.statuses.isEmpty && future.today == DayStatus.none)
}

@Test func fullInCurrentCountsOnlyAfterReset() {
    var list = (1...3).map { (oct($0), full()) }
    list += [(oct(5), full()), (oct(6), full())]   // 4-го пропуск без заморозки
    let s = StreakCalculator.summarize(days: days(list), today: oct(6), goalSeconds: goal)
    #expect(s.current == 2)
    #expect(s.fullInCurrent == 2)
    #expect(s.fullInRow == 2)
    #expect(s.longest == 3)
}

/// День, где было время, но ни одного завершённого упражнения, — не занятие.
@Test func zeroExerciseDayAtStartIsNotFirstDay() {
    let idle = DayActivity(activeSeconds: 900, completedExercises: 0)
    let s = StreakCalculator.summarize(days: days([(oct(1), idle), (oct(2), full())]), today: oct(2), goalSeconds: goal)
    #expect(s.statuses[oct(1)] == nil)
    #expect(s.current == 1 && s.longest == 1)
}

@Test func zeroExerciseDayInMiddleBreaksStreakWithoutFreeze() {
    let idle = DayActivity(activeSeconds: 900, completedExercises: 0)
    let list = [(oct(1), full()), (oct(2), idle), (oct(3), full())]
    // 4-е (сегодня) ещё без занятий: у 2-го следующий день набрал одну цель, а не две — разрыв.
    let s = StreakCalculator.summarize(days: days(list), today: oct(4), goalSeconds: goal)
    #expect(s.statuses[oct(2)] == DayStatus.none)
    #expect(s.current == 1)
    #expect(s.fullInCurrent == 1)
    #expect(s.longest == 1)
}

// MARK: - Цель дня за каждым днём (Task 15 фазы 5)

/// Вчера 10 минут при цели 10 — полный огонь; цель подняли до 20 — вчера остаётся полным,
/// а сегодня 15 минут — половинный (сегодня всегда по текущей цели).
@Test func pastDayKeepsItsOwnGoal() {
    let yesterday = DayActivity(activeSeconds: 600, completedExercises: 2, goalSeconds: 600)
    let today = DayActivity(activeSeconds: 900, completedExercises: 3, goalSeconds: 600)
    let before = StreakCalculator.summarize(days: days([(oct(23), yesterday)]), today: oct(24), goalSeconds: 600)
    #expect(before.statuses[oct(23)] == .full)

    let after = StreakCalculator.summarize(days: days([(oct(23), yesterday), (oct(24), today)]),
                                           today: oct(24), goalSeconds: 1200)
    #expect(after.statuses[oct(23)] == .full)
    #expect(after.statuses[oct(24)] == .half && after.today == .half)
    #expect(after.current == 2 && after.fullInCurrent == 1)
}

/// Сегодня записанная цель не действует: снизили цель — сегодня сразу по новой.
@Test func todayAlwaysFollowsCurrentGoal() {
    let today = DayActivity(activeSeconds: 400, completedExercises: 1, goalSeconds: 1200)
    let s = StreakCalculator.summarize(days: days([(oct(24), today)]), today: oct(24), goalSeconds: 300)
    #expect(s.today == .full)
}

/// День без записанной цели (до поколения 5) считается по текущей цели.
@Test func dayWithoutStoredGoalUsesCurrentGoal() {
    let unknown = DayActivity(activeSeconds: 600, completedExercises: 1)
    #expect(unknown.goalSeconds == nil)
    let low = StreakCalculator.summarize(days: days([(oct(23), unknown)]), today: oct(24), goalSeconds: 600)
    #expect(low.statuses[oct(23)] == .full)
    let high = StreakCalculator.summarize(days: days([(oct(23), unknown)]), today: oct(24), goalSeconds: 1200)
    #expect(high.statuses[oct(23)] == .half)
}

/// Свои цели дней влияют и на заморозки: 7 полных дней по их целям дают заморозку при любой текущей цели.
@Test func freezesFollowPerDayGoals() {
    let list = (1...7).map { (oct($0), DayActivity(activeSeconds: 300, completedExercises: 1, goalSeconds: 300)) }
    let s = StreakCalculator.summarize(days: days(list), today: oct(9), goalSeconds: 1800)
    #expect(s.statuses[oct(8)] == .frozen)
    #expect(s.current == 8)
}

// MARK: - Метрики дней «Заходил» и «Цель» (фаза 6a, Task 5)

@Test func visitAndGoalMetricsCountRunsAndTotals() {
    let s = StreakCalculator.summarize(days: days([("2026-10-20", full()), ("2026-10-21", half()), ("2026-10-22", full())]),
                                       today: "2026-10-22", goalSeconds: goal)
    #expect(s.visitCurrent == 3 && s.visitLongest == 3 && s.visitTotal == 3)
    #expect(s.goalCurrent == 1 && s.goalLongest == 1 && s.goalTotal == 2)
}

/// Заморозка спасает огонь, но не «Заходил» и не «Цель».
@Test func frozenDayBreaksVisitAndGoalRuns() {
    var list: [(String, DayActivity)] = []
    for d in 1...7 { list.append((oct(d), full())) }
    list.append(("2026-10-09", full()))   // 8-е пропущено, его закрыла заморозка
    let s = StreakCalculator.summarize(days: days(list), today: "2026-10-09", goalSeconds: goal)
    #expect(s.current == 9 && s.statuses["2026-10-08"] == .frozen)
    #expect(s.visitCurrent == 1 && s.visitLongest == 7 && s.visitTotal == 8)
    #expect(s.goalCurrent == 1 && s.goalLongest == 7 && s.goalTotal == 8)
}

/// Сегодня ещё не занимались или день пока половинный: серии не обрываются.
@Test func todayDoesNotBreakVisitOrGoalRunsBeforeItEnds() {
    let notYet = StreakCalculator.summarize(days: days([("2026-10-22", full()), ("2026-10-23", full())]),
                                            today: "2026-10-24", goalSeconds: goal)
    #expect(notYet.visitCurrent == 2 && notYet.goalCurrent == 2 && notYet.goalTotal == 2)
    let halfToday = StreakCalculator.summarize(
        days: days([("2026-10-22", full()), ("2026-10-23", full()), ("2026-10-24", half())]),
        today: "2026-10-24", goalSeconds: goal)
    #expect(halfToday.visitCurrent == 3 && halfToday.visitTotal == 3)
    #expect(halfToday.goalCurrent == 2 && halfToday.goalTotal == 2)
}

/// Прошлый день — по своей цели; день только с брошенными упражнениями не «Заходил».
@Test func visitAndGoalUseEachDaysGoalAndCompletedExercises() {
    let s = StreakCalculator.summarize(days: days([
        ("2026-10-20", DayActivity(activeSeconds: 700, completedExercises: 1, goalSeconds: 1200)),   // половинный
        ("2026-10-21", DayActivity(activeSeconds: 900, completedExercises: 0)),                      // только брошенные
        ("2026-10-22", full()),
    ]), today: "2026-10-22", goalSeconds: goal)
    #expect(s.visitCurrent == 1 && s.visitLongest == 1 && s.visitTotal == 2)
    #expect(s.goalCurrent == 1 && s.goalTotal == 1)
}

@Test func emptyHistoryHasZeroDayMetrics() {
    let s = StreakCalculator.summarize(days: [:], today: "2026-10-24", goalSeconds: goal)
    #expect(s.visitCurrent == 0 && s.visitTotal == 0 && s.goalCurrent == 0 && s.goalTotal == 0)
}

/// Новые метрики ничего не меняют в огне: поля огня, заморозки и статусы прежние, а `StreakSummary`
/// прежним инициализатором (без метрик дней) даёт нули.
@Test func dayMetricsDoNotChangeFlameFreezesAndStatuses() {
    // 1–3 полные, 4 половинный, 5 пропуск без заморозки (обрыв), 6 полный, сегодня (7) ещё пусто.
    let list = [(oct(1), full()), (oct(2), full()), (oct(3), full()), (oct(4), half()), (oct(6), full())]
    let s = StreakCalculator.summarize(days: days(list), today: oct(7), goalSeconds: goal)
    #expect(s.current == 1 && s.fullInRow == 1 && s.fullInCurrent == 1)
    #expect(s.freezes == 0 && s.longest == 4 && s.today == DayStatus.none)
    #expect(s.statuses == [oct(1): .full, oct(2): .full, oct(3): .full, oct(4): .half,
                           oct(5): DayStatus.none, oct(6): .full, oct(7): DayStatus.none])
    #expect(s.visitCurrent == 1 && s.visitLongest == 4 && s.visitTotal == 5)
    #expect(s.goalCurrent == 1 && s.goalLongest == 3 && s.goalTotal == 4)

    let legacy = StreakSummary(current: 1, fullInRow: 1, fullInCurrent: 1, freezes: 0, longest: 4,
                               today: .none, statuses: s.statuses)
    #expect(legacy.visitCurrent == 0 && legacy.visitLongest == 0 && legacy.visitTotal == 0)
    #expect(legacy.goalCurrent == 0 && legacy.goalLongest == 0 && legacy.goalTotal == 0)
}

/// Цель дня для «Цели» берётся та же, что для огня: прошлый день по своей, сегодня по текущей.
@Test func goalMetricFollowsPerDayGoalsLikeTheFlame() {
    let list = [(oct(22), DayActivity(activeSeconds: 300, completedExercises: 1, goalSeconds: 300)),   // полный по своей цели
                (oct(23), DayActivity(activeSeconds: 300, completedExercises: 1, goalSeconds: 600)),   // половинный
                (oct(24), DayActivity(activeSeconds: 400, completedExercises: 1, goalSeconds: 1200))]  // сегодня: по текущей (300)
    let s = StreakCalculator.summarize(days: days(list), today: oct(24), goalSeconds: 300)
    #expect(s.statuses[oct(22)] == .full && s.statuses[oct(23)] == .half && s.statuses[oct(24)] == .full)
    #expect(s.goalCurrent == 1 && s.goalTotal == 2 && s.goalLongest == 1)
    #expect(s.visitCurrent == 3 && s.visitTotal == 3)
}
