import Testing
@testable import TypingCore

// Починка серии (6e, §10.4, решения 2–4 плана): двойная цель на следующий день спасает пропущенный день.
// Цель в этих тестах — 10 минут (600 секунд), двойная — 20 минут.

private let goal = 600.0
private func full() -> DayActivity { DayActivity(activeSeconds: 700, completedExercises: 3) }
private func half() -> DayActivity { DayActivity(activeSeconds: 60, completedExercises: 1) }
private func minutes(_ value: Double, goalSeconds: Double? = nil) -> DayActivity {
    DayActivity(activeSeconds: value * 60, completedExercises: 2, goalSeconds: goalSeconds)
}
private func days(_ list: [(String, DayActivity)]) -> [String: DayActivity] { Dictionary(uniqueKeysWithValues: list) }
private func oct(_ day: Int) -> String { day < 10 ? "2026-10-0\(day)" : "2026-10-\(day)" }

/// Пять полных дней 1–5 октября: заморозок ещё нет (нужно семь).
private func fiveFull() -> [(String, DayActivity)] { (1...5).map { (oct($0), full()) } }

@Test func repairConstantsAndDayStatusRawValue() {
    #expect(StreakCalculator.repairCooldownDays == 7)
    #expect(StreakCalculator.repairGoalFactor == 2.0)
    #expect(DayStatus.repaired.rawValue == "repaired")
}

@Test func doubleGoalNextDayRepairsAMissedDay() {
    let list = fiveFull() + [(oct(7), minutes(20))]
    let s = StreakCalculator.summarize(days: days(list), today: oct(7), goalSeconds: goal)
    #expect(s.statuses[oct(6)] == .repaired)
    #expect(s.current == 7 && s.longest == 7)
    #expect(s.freezes == 0 && !s.repairPending)
    #expect(s.fullInCurrent == 6 && s.fullInRow == 1)   // починенный день не полный
}

@Test func repairResetsTheFullRowSoItDoesNotEarnAFreeze() {
    // Шесть полных, пропуск, двойная цель: без сброса седьмым «полным подряд» стал бы день X+1 и дал заморозку.
    var list: [(String, DayActivity)] = (1...6).map { (oct($0), full()) }
    list.append((oct(8), minutes(20)))
    let s = StreakCalculator.summarize(days: days(list), today: oct(8), goalSeconds: goal)
    #expect(s.statuses[oct(7)] == .repaired)
    #expect(s.fullInRow == 1 && s.freezes == 0 && s.current == 8)
}

@Test func lessThanDoubleGoalDoesNotRepair() {
    let list = fiveFull() + [(oct(7), minutes(19))]   // 1,9 цели
    let s = StreakCalculator.summarize(days: days(list), today: oct(7), goalSeconds: goal)
    #expect(s.statuses[oct(6)] == DayStatus.none)
    // Сегодня и не набрано — это «на волоске», но день пока не починен; а в прошлом — разрыв.
    let past = StreakCalculator.summarize(days: days(list), today: oct(8), goalSeconds: goal)
    #expect(past.statuses[oct(6)] == DayStatus.none && !past.repairPending)
    #expect(past.current == 1 && past.longest == 5)
}

@Test func aFreezeIsSpentBeforeARepair() {
    var list: [(String, DayActivity)] = (1...7).map { (oct($0), full()) }   // седьмой полный день даёт заморозку
    list.append((oct(9), minutes(20)))
    let s = StreakCalculator.summarize(days: days(list), today: oct(9), goalSeconds: goal)
    #expect(s.statuses[oct(8)] == .frozen)
    #expect(!s.statuses.values.contains(.repaired))
    #expect(s.freezes == 0 && s.current == 9)
}

@Test func twoMissedDaysInARowOnlyTheSecondCanBeRepaired() {
    // Заморозка (одна) закрывает первый пропуск, второй чинится двойной целью на третий день.
    var list: [(String, DayActivity)] = (1...7).map { (oct($0), full()) }
    list.append((oct(10), minutes(20)))
    let s = StreakCalculator.summarize(days: days(list), today: oct(10), goalSeconds: goal)
    #expect(s.statuses[oct(8)] == .frozen && s.statuses[oct(9)] == .repaired)
    #expect(s.current == 10)
    // Без заморозок два пропуска подряд: у первого следующий день пуст — разрыв.
    let broken = StreakCalculator.summarize(days: days(fiveFull() + [(oct(8), minutes(20))]),
                                            today: oct(8), goalSeconds: goal)
    #expect(broken.statuses[oct(6)] == DayStatus.none && broken.statuses[oct(7)] == DayStatus.none)
    #expect(broken.current == 1)
}

@Test func repairCooldownIsSevenDays() {
    // Починка 6-го; пропуск 12-го (6 дней спустя) не чинится, пропуск 13-го (7 дней) — чинится.
    func summary(missed: Int) -> StreakSummary {
        var list = fiveFull() + [(oct(7), minutes(20))]
        for d in 8...(missed - 1) { list.append((oct(d), full())) }
        list.append((oct(missed + 1), minutes(20)))
        return StreakCalculator.summarize(days: days(list), today: oct(missed + 1), goalSeconds: goal)
    }
    let tooSoon = summary(missed: 12)
    #expect(tooSoon.statuses[oct(6)] == .repaired && tooSoon.statuses[oct(12)] == DayStatus.none)
    #expect(tooSoon.current == 1)
    let allowed = summary(missed: 13)
    #expect(allowed.statuses[oct(6)] == .repaired && allowed.statuses[oct(13)] == .repaired)
    #expect(allowed.current == 14)
}

@Test func todayBeingTheNextDayShowsAPendingRepairAndKeepsTheStreakWhole() {
    // Вчера пропущен, сегодня набрано 8 из 20 минут: серия «на волоске».
    let list = fiveFull() + [(oct(7), minutes(8))]
    let s = StreakCalculator.summarize(days: days(list), today: oct(7), goalSeconds: goal)
    #expect(s.repairPending && s.repairDay == oct(6))
    #expect(s.repairNeedSeconds == 12 * 60 && s.repairTargetSeconds == 20 * 60)
    #expect(s.repairStreak == 6)           // пять дней и сам пропущенный
    #expect(s.current == 7)                // сегодня уже засчитан (половинный) — на единицу больше
    #expect(s.statuses[oct(6)] == DayStatus.none && s.today == .half)
    // Сегодня ещё ничего не сделано: серия целая, равна `repairStreak`.
    let idle = StreakCalculator.summarize(days: days(fiveFull()), today: oct(7), goalSeconds: goal)
    #expect(idle.repairPending && idle.repairStreak == 6 && idle.current == 6)
    #expect(idle.repairNeedSeconds == 20 * 60 && idle.statuses[oct(6)] == DayStatus.none)
    // Набрана двойная цель: день починен, ожидания нет.
    let done = StreakCalculator.summarize(days: days(fiveFull() + [(oct(7), minutes(20))]), today: oct(7),
                                          goalSeconds: goal)
    #expect(done.statuses[oct(6)] == .repaired && !done.repairPending && done.repairDay == nil)
    #expect(done.repairStreak == 0 && done.repairNeedSeconds == 0 && done.repairTargetSeconds == 0)
}

@Test func noPendingRepairWithoutASeriesAFreezeOrAFreeCooldown() {
    // Серия уже оборвалась (пропущены 2-е и 3-е): нечего спасать.
    let fresh = StreakCalculator.summarize(days: days([(oct(1), full())]), today: oct(4), goalSeconds: goal)
    #expect(!fresh.repairPending && fresh.current == 0)
    // Есть заморозка — день замораживается, а не «на волоске».
    let frozen = StreakCalculator.summarize(days: days((1...7).map { (oct($0), full()) }), today: oct(9),
                                            goalSeconds: goal)
    #expect(!frozen.repairPending && frozen.statuses[oct(8)] == .frozen)
    // Починка была менее 7 дней назад — не «на волоске».
    let list = fiveFull() + [(oct(7), minutes(20))] + (8...11).map { (oct($0), full()) }
    let cooldown = StreakCalculator.summarize(days: days(list), today: oct(13), goalSeconds: goal)
    #expect(!cooldown.repairPending && cooldown.statuses[oct(12)] == DayStatus.none)
}

@Test func repairUsesTheGoalOfTheNextDayNotOfTheMissedOne() {
    // Цель 7-го дня записана 5 минут: двойная — 10; текущая цель 10 дала бы 20.
    let recorded = StreakCalculator.summarize(
        days: days(fiveFull() + [(oct(7), minutes(10, goalSeconds: 300))]), today: oct(8), goalSeconds: goal)
    #expect(recorded.statuses[oct(6)] == .repaired)
    // Запись 15 минут: двойная — 30, набрано 20 — не починено.
    let higher = StreakCalculator.summarize(
        days: days(fiveFull() + [(oct(7), minutes(20, goalSeconds: 900))]), today: oct(8), goalSeconds: goal)
    #expect(higher.statuses[oct(6)] == DayStatus.none)
    // Без записи — по текущей цели (20 минут).
    let unknown = StreakCalculator.summarize(days: days(fiveFull() + [(oct(7), minutes(20))]), today: oct(8),
                                             goalSeconds: goal)
    #expect(unknown.statuses[oct(6)] == .repaired)
    // Сегодня запись цели не действует: у сегодняшнего дня — текущая.
    let today = StreakCalculator.summarize(
        days: days(fiveFull() + [(oct(7), minutes(10, goalSeconds: 300))]), today: oct(7), goalSeconds: goal)
    #expect(today.repairPending && today.repairTargetSeconds == 1200 && today.repairNeedSeconds == 600)
}

@Test func visitAndGoalRunsStillBreakOnARepairedDay() {
    let list = fiveFull() + [(oct(7), minutes(20))]
    let s = StreakCalculator.summarize(days: days(list), today: oct(7), goalSeconds: goal)
    #expect(s.statuses[oct(6)] == .repaired)
    #expect(s.visitCurrent == 1 && s.visitLongest == 5 && s.visitTotal == 6)
    #expect(s.goalCurrent == 1 && s.goalLongest == 5 && s.goalTotal == 6)
}

/// Свойство «не короче»: починка не укорачивает ни текущую серию, ни рекорд и меняет статусы только `none → repaired`.
@Test func repairNeverShortensTheStreakAndOnlyTurnsNoneIntoRepaired() {
    // F — полный день, H — половинный, D — двойная цель, «-» — пропуск.
    let histories = [
        "FFFFFF-DFFFFFFFF-DFFFF",
        "FFFFFFFFFFFFFFFFF--DF---D",
        "HHH-DHH-HDFFFFFFF-D",
        "FFFFFFF-FFFFFFF--D--DDFFFFFFFF-D",
        "FFFFFF-D-FFFFFFFFFFFFFFFFFFFFD-D",
        // «На волоске»: пропуск вчера, сегодня ничего или только одна цель.
        "FFFFF-",
        "FFFFF-F",
    ]
    for history in histories {
        var list: [(String, DayActivity)] = []
        var key = "2026-09-01"
        for symbol in history {
            switch symbol {
            case "F": list.append((key, full()))
            case "H": list.append((key, half()))
            case "D": list.append((key, minutes(20)))
            default: break
            }
            key = StreakCalculator.dayKey(key, offset: 1)
        }
        let today = StreakCalculator.dayKey("2026-09-01", offset: history.count - 1)
        let with = StreakCalculator.summarize(days: days(list), today: today, goalSeconds: goal, allowRepair: true)
        let without = StreakCalculator.summarize(days: days(list), today: today, goalSeconds: goal,
                                                 allowRepair: false)
        #expect(with.current >= without.current, "\(history): серия")
        #expect(with.longest >= without.longest, "\(history): рекорд")
        #expect(with.statuses.keys.sorted() == without.statuses.keys.sorted(), "\(history)")
        for (day, status) in with.statuses where status != without.statuses[day] {
            #expect(without.statuses[day] == DayStatus.none && status == .repaired, "\(history): \(day)")
        }
        #expect(!without.statuses.values.contains(.repaired) && !without.repairPending)
    }
}
