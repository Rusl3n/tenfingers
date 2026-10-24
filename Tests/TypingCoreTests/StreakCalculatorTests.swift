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
    let s = StreakCalculator.summarize(days: days([("2026-10-20", full()), ("2026-10-22", full())]),
                                       today: "2026-10-22", goalSeconds: goal)
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
    let list = (1...3).map { (oct($0), full()) }   // 4-го пропуск, 5-го (сегодня) ещё не занимались
    let s = StreakCalculator.summarize(days: days(list), today: oct(5), goalSeconds: goal)
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
    let s = StreakCalculator.summarize(days: days(list), today: oct(3), goalSeconds: goal)
    #expect(s.statuses[oct(2)] == DayStatus.none)
    #expect(s.current == 1)
    #expect(s.fullInCurrent == 1)
    #expect(s.longest == 1)
}
