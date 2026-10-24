import Foundation
import Testing
@testable import TypingCore

private func utc() -> Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    return calendar
}

private func date(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
    utc().date(from: DateComponents(year: 2026, month: 3, day: day, hour: hour, minute: minute))!
}

private let noon = date(10, 12)
private func situation(streak: Int = 5, today: DayStatus = .none, minutesLeft: Int = 6) -> ReminderSituation {
    ReminderSituation(streak: streak, todayStatus: today, minutesLeft: minutesLeft)
}

private func plan(now: Date = noon, config: ReminderConfig = ReminderConfig(), situation: ReminderSituation = situation(),
                  dayStartHour: Int = 4) -> [PlannedReminder] {
    ReminderPlanner.plan(now: now, config: config, situation: situation, dayStartHour: dayStartHour, calendar: utc())
}

private func phrase(_ reminder: PlannedReminder) -> ReminderCatalog.Phrase {
    ReminderCatalog.phrases.first { $0.key == reminder.line.key }!
}

private func hours(_ plan: [PlannedReminder]) -> [Int] {
    plan.map { utc().component(.hour, from: $0.date) }
}

// MARK: - dailyMinutes

@Test func dailyMinutesPerMode() {
    #expect(ReminderConfig().dailyMinutes() == [1200])
    #expect(ReminderConfig(mode: .thrice).dailyMinutes() == [600, 900, 1200])
    // Без повторов и по возрастанию.
    #expect(ReminderConfig(mode: .thrice, thriceMinutes: [900, 600, 900]).dailyMinutes() == [600, 900])
    #expect(ReminderConfig(mode: .interval).dailyMinutes() == [600, 780, 960, 1140])
    #expect(ReminderConfig(mode: .interval, fromHour: 10, toHour: 10).dailyMinutes() == [600])
    #expect(ReminderConfig(mode: .interval, fromHour: 15, toHour: 9).dailyMinutes() == [900])
    #expect(ReminderConfig(mode: .interval, fromHour: 8, toHour: 12, intervalHours: 0).dailyMinutes()
        == [480, 540, 600, 660, 720])
    #expect(ReminderConfig(mode: .interval, fromHour: 0, toHour: 23, intervalHours: 9).dailyMinutes()
        == [0, 240, 480, 720, 960, 1200])
    // Значения вне суток приводятся к 0..<1440.
    #expect(ReminderConfig(onceMinute: 5000).dailyMinutes() == [1439])
    #expect(ReminderConfig(onceMinute: -4).dailyMinutes() == [0])
}

// MARK: - Расписание

@Test func onceSchedulesSevenDaysStartingToday() {
    let result = plan()
    #expect(result.count == 7)
    #expect(result.map(\.date) == (10...16).map { date($0, 20) })
    #expect(result.map(\.id) == (10...16).map { "reminder.2026-03-\($0)T20:00" })
    // Сегодня: серия под угрозой, ступень «мягко».
    let first = phrase(result[0])
    #expect(first.stage == .soft && first.need != .minutes)
    #expect(result[0].line.streak == (first.need == .streak ? 5 : 0))
}

@Test func fullDayHasNoRemindersToday() {
    let result = plan(situation: situation(today: .full))
    #expect(result.map(\.date) == (11...17).map { date($0, 20) })
    #expect(result.map(\.id) == (11...17).map { "reminder.2026-03-\($0)T20:00" })
    #expect(plan(situation: situation(today: .frozen)).first?.date == date(11, 20))
}

@Test func thriceUsesDefaultTimes() {
    let result = plan(now: date(10, 8), config: ReminderConfig(mode: .thrice))
    #expect(result.count == 21)
    #expect(result.prefix(3).map(\.date) == [date(10, 10), date(10, 15), date(10, 20)])
}

@Test func thriceCountsOnlyTheFutureOfToday() {
    let result = plan(now: date(10, 16), config: ReminderConfig(mode: .thrice))
    #expect(result.count == 3 * 7 - 2)
    #expect(result.first?.date == date(10, 20))
    #expect(result.map(\.id).last == "reminder.2026-03-16T20:00")
}

@Test func intervalStepsFromTo() {
    let result = plan(now: date(10, 8), config: ReminderConfig(mode: .interval))
    #expect(hours(Array(result.prefix(4))) == [10, 13, 16, 19])
    #expect(result.count == 28)
}

@Test func intervalWithToNotAfterFromGivesSingleSlot() {
    let config = ReminderConfig(mode: .interval, fromHour: 18, toHour: 9)
    let result = plan(now: date(10, 8), config: config)
    #expect(result.count == 7)
    #expect(Set(hours(result)) == [18])
}

@Test func pendingLimitIsSixtyAndStopsInFifthDay() {
    let config = ReminderConfig(mode: .interval, fromHour: 10, toHour: 21, intervalHours: 1)
    let result = plan(now: date(10, 8), config: config)
    #expect(result.count == ReminderPlanner.maxPending)
    #expect(result.count == 60)
    #expect(result.last?.date == date(14, 21))
    #expect(Set(result.map(\.id)).count == 60)
    #expect(result.map(\.date) == result.map(\.date).sorted())
}

@Test func passedTimeStartsTomorrow() {
    #expect(plan(now: date(10, 21)).first?.date == date(11, 20))
    #expect(plan(now: date(10, 20)).first?.date == date(11, 20))
    #expect(plan(now: date(10, 21)).count == 7)
}

@Test func reminderBeforeDayStartBelongsToPreviousLogicalDay() {
    let config = ReminderConfig(onceMinute: 120)
    // Завтра в 02:00 — ещё сегодняшний логический день (полный огонь его закрывает).
    let result = plan(now: date(10, 23), config: config, situation: situation(today: .full))
    #expect(result.count == 7)
    #expect(result.first?.date == date(12, 2))
}

// MARK: - Ступени

@Test func escalationFollowsPositionInDailySchedule() {
    let config = ReminderConfig(mode: .interval, escalating: true)
    let result = plan(now: date(10, 8), config: config)
    let stages = result.prefix(4).map { phrase($0).stage }
    #expect(stages == [.soft, .insistent, .drama, .drama])
}

@Test func withoutEscalationEverythingIsSoft() {
    let config = ReminderConfig(mode: .interval, escalating: false)
    #expect(plan(now: date(10, 8), config: config).allSatisfy { phrase($0).stage == .soft })
}

@Test func escalationUsesSchedulePositionNotRemainingSlots() {
    let config = ReminderConfig(mode: .thrice, escalating: true)
    // Сейчас 16:00: сегодня остаётся только 20:00 — третье по расписанию дня, значит драма.
    let result = plan(now: date(10, 16), config: config)
    #expect(result.first?.date == date(10, 20))
    #expect(phrase(result[0]).stage == .drama)
    // Завтра 10:00 — снова мягко.
    #expect(phrase(result[1]).stage == .soft)
}

// MARK: - Тексты

@Test func sameSlotGivesSameTextRegardlessOfNow() {
    let config = ReminderConfig(mode: .thrice, escalating: true)
    let early = plan(now: date(10, 6), config: config)
    let later = plan(now: date(10, 12), config: config)
    let earlyByDate = Dictionary(uniqueKeysWithValues: early.map { ($0.date, $0.line.key) })
    for item in later { #expect(earlyByDate[item.date] == item.line.key) }
    #expect(plan(now: date(10, 6), config: config) == early)
}

@Test func futureDaysUseOnlyTextsWithoutNumbers() {
    let config = ReminderConfig(mode: .thrice, escalating: true)
    let result = plan(now: date(10, 8), config: config)
    for item in result where item.date >= date(11, 0) {
        #expect(phrase(item).need == .none)
        #expect(item.line.streak == 0 && item.line.minutes == 0)
    }
}

@Test func halfDayUsesMinutesOrPlainTexts() {
    let result = plan(config: ReminderConfig(mode: .thrice, escalating: true), situation: situation(today: .half, minutesLeft: 7))
    for item in result.prefix(1) {
        let found = phrase(item)
        #expect(found.need != .streak)
        #expect(item.line.minutes == (found.need == .minutes ? 7 : 0))
    }
    for item in plan(now: date(10, 8), config: ReminderConfig(mode: .thrice, escalating: true),
                     situation: situation(today: .half, minutesLeft: 7)).prefix(3) {
        #expect(phrase(item).need != .streak)
    }
}

@Test func noStreakTodayUsesPlainTexts() {
    let result = plan(now: date(10, 8), config: ReminderConfig(mode: .thrice, escalating: true),
                      situation: situation(streak: 0, today: .none))
    #expect(result.allSatisfy { phrase($0).need == .none })
}

@Test func adultHumorOffNeverPlansAdultTexts() {
    let config = ReminderConfig(mode: .interval, fromHour: 0, toHour: 23, intervalHours: 1, tone: .funny,
                                escalating: true, adultHumor: false)
    #expect(plan(now: date(10, 0), config: config).allSatisfy { !phrase($0).adult })
}

@Test func toneNormalNeverPlansFunnyTexts() {
    let config = ReminderConfig(mode: .thrice, tone: .normal, escalating: true)
    #expect(plan(config: config).allSatisfy { phrase($0).tone == .normal })
}

// MARK: - Идентификаторы

/// Идентификатор — время срабатывания (по календарю планировщика), а не номер по порядку: напоминание на то же
/// время получает тот же идентификатор при любом «сейчас». Иначе после первого сработавшего все сдвигались бы,
/// и разница с уже поставленными (`ReminderScheduler`) каждый раз была бы полной.
@Test func idsAreStableAcrossReplanning() {
    let morning = plan(now: date(10, 8), config: ReminderConfig(mode: .thrice))
    let evening = plan(now: date(10, 16), config: ReminderConfig(mode: .thrice))
    let byID = Dictionary(uniqueKeysWithValues: morning.map { ($0.id, $0.date) })
    #expect(evening.allSatisfy { byID[$0.id] == $0.date })
    #expect(Set(morning.map(\.id)).count == morning.count)
    #expect(ReminderPlanner.id(for: date(9, 7, 5), calendar: utc()) == "reminder.2026-03-09T07:05")
}

/// Весенний перевод часов: 02:00 не существует и сдвигается на 03:00. Если в расписании есть и 02:00, и 03:00,
/// в этот день остаётся одно напоминание на 03:00, а не два с одним идентификатором (иначе одно терялось бы,
/// а разница с поставленными не сходилась бы никогда).
@Test func springForwardDoesNotDuplicateASlot() {
    var berlin = Calendar(identifier: .gregorian)
    berlin.timeZone = TimeZone(identifier: "Europe/Berlin")!
    let now = berlin.date(from: DateComponents(year: 2027, month: 3, day: 27, hour: 12))!
    let config = ReminderConfig(mode: .thrice, thriceMinutes: [120, 180, 600])
    let result = ReminderPlanner.plan(now: now, config: config, situation: situation(), dayStartHour: 4,
                                      calendar: berlin)
    #expect(Set(result.map(\.id)).count == result.count)
    #expect(Set(result.map(\.date)).count == result.count)
    let switchDay = result.filter { berlin.component(.day, from: $0.date) == 28 }
    #expect(switchDay.map { berlin.component(.hour, from: $0.date) } == [3, 10])
}
