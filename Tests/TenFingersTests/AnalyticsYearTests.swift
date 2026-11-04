import AppKit
import Foundation
import SwiftData
import Testing
import TypingCore
@testable import TenFingers

// MARK: - Помощники

private let msk = TimeZone(identifier: "Europe/Moscow")!
private let ruLocale = Locale(identifier: "ru_RU")
/// Диапазон дат в ICU разделяют тире разной длины и узкие пробелы: для сравнения приводятся к «–» и обычному пробелу.
private func plain(_ text: String) -> String {
    var result = text
    for (from, to) in [("\u{2014}", "\u{2013}"), ("\u{2009}", " "), ("\u{202F}", " "), ("\u{00A0}", " ")] {
        result = result.replacingOccurrences(of: from, with: to)
    }
    return result
}

/// «Сейчас» для подписи недель: 3 ноября 2026.
private let now = at("2026-11-03 10:00")

/// «2026-11-03 09:00» по Москве.
private func at(_ text: String) -> Date {
    let parts = text.split(whereSeparator: { $0 == "-" || $0 == " " || $0 == ":" }).compactMap { Int($0) }
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = msk
    return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2], hour: parts[3],
                                              minute: parts[4]))!
}

@MainActor private func insertSession(_ context: ModelContext, ended: String, day: String) {
    let end = at(ended)
    context.insert(SessionRecord(
        mode: "course", language: "ru", lessonId: nil, startedAt: end.addingTimeInterval(-200), endedAt: end,
        logicalDay: day, activeSeconds: 200, chars: 80, errorCount: 1, cpm: 160, accuracy: 0.99,
        completed: true, hintLevel: "full", maxErrorStreak: 1, wrongKeystrokes: 1, exerciseKind: nil))
    let record = DayRecord(logicalDay: day)
    record.activeSeconds = 200
    record.completedExercises = 1
    record.goalSeconds = 600
    context.insert(record)
}

/// Журнал опыта: занятия в трёх неделях последних 26 (W45, W43, W38) и одно — задолго до окна (W09).
@MainActor private func ledgerWithThreeWeeks() throws -> ExperienceLedger {
    let container = try ModelStore.makeContainer(inMemory: true)
    let context = container.mainContext
    insertSession(context, ended: "2026-11-02 20:00", day: "2026-11-02")
    insertSession(context, ended: "2026-10-20 20:00", day: "2026-10-20")
    insertSession(context, ended: "2026-09-15 20:00", day: "2026-09-15")
    insertSession(context, ended: "2026-03-02 20:00", day: "2026-03-02")
    try context.save()
    let service = AchievementService(recorder: ResultRecorder(context: context, dayStartHour: 4),
                                     goalSeconds: { 600 }, timeZone: msk, now: { at("2026-11-03 10:00") },
                                     cache: AchievementFactsCache())
    return try YearLoader(context: context, service: service).state().ledger
}

private func result(_ id: ChallengeId, done: Bool, target: Int = 5, at date: Date? = nil) -> ChallengeResult {
    ChallengeResult(id: id, progress: done ? target : 1, target: target, completedAt: done ? (date ?? Date(timeIntervalSince1970: 0)) : nil)
}

private let parameters = ChallengeParameters(goalMinutes: 10, cpm: 100)

private func week(_ key: String, done: [Bool]) -> ChallengePeriodResult {
    let ids: [ChallengeId] = [.weekGoal5, .weekVisit7, .weekChars]
    return ChallengePeriodResult(period: .week(key), parameters: parameters,
                                 results: zip(ids, done).map { result($0, done: $1) }, allDoneAt: nil)
}

// MARK: - Опыт по неделям

@MainActor @Test func experienceChartHas26WeeksWithEmptyOnesAtZero() throws {
    let ledger = try ledgerWithThreeWeeks()
    let model = ExperienceChartModel.make(ledger: ledger, today: "2026-11-03")
    #expect(model.points.count == 26)
    // По возрастанию, последняя точка — неделя сегодняшнего дня; соседние недели идут подряд.
    #expect(model.points.last?.week == "2026-W45")
    #expect(model.points.first?.week == "2026-W20")
    #expect(model.points.map(\.week) == model.points.map(\.week).sorted())
    #expect(Set(model.points.map(\.week)).count == 26)
    #expect(model.points.last?.firstDay == "2026-11-02")
    #expect(model.points.first?.firstDay == "2026-05-11")

    let weekly = Dictionary(uniqueKeysWithValues: ledger.weekly().map { ($0.week, $0.amount) })
    for point in model.points { #expect(point.amount == (weekly[point.week] ?? 0), "неделя \(point.week)") }
    let filled = model.points.filter { $0.amount > 0 }.map(\.week)
    #expect(filled == ["2026-W38", "2026-W43", "2026-W45"])
    #expect(model.points.filter { $0.amount == 0 }.count == 23)
    // «Всего» — весь опыт, в том числе вне окна графика (W09 в график не попала).
    #expect(model.total == ledger.total)
    #expect(model.total > model.points.map(\.amount).reduce(0, +))
    #expect(model.level == LevelCurve.level(forExperience: ledger.total))
    #expect(model.title == LevelTitle.of(level: model.level))
}

@MainActor @Test func experienceChartOfAnEmptyLedgerIsAllZeros() throws {
    let container = try ModelStore.makeContainer(inMemory: true)
    let service = AchievementService(recorder: ResultRecorder(context: container.mainContext, dayStartHour: 4),
                                     goalSeconds: { 600 }, timeZone: msk, now: { at("2026-11-03 10:00") },
                                     cache: AchievementFactsCache())
    let ledger = try YearLoader(context: container.mainContext, service: service).state().ledger
    let model = ExperienceChartModel.make(ledger: ledger, today: "2026-11-03", weeks: 4)
    #expect(model.points.count == 4)
    #expect(model.points.allSatisfy { $0.amount == 0 })
    #expect(model.total == 0 && model.level == 1 && !model.hasData)
}

@Test func experienceChartWeeksCrossTheYearBoundary() {
    let ledger = Experience.ledger(AchievementFacts(timeZone: msk, now: at("2027-01-05 10:00")))
    let model = ExperienceChartModel.make(ledger: ledger, today: "2027-01-05", weeks: 3)
    #expect(model.points.map(\.week) == ["2026-W52", "2026-W53", "2027-W01"])
}

// MARK: - История испытаний

@Test func weekRowShowsHowManyOfThreeAreDone() {
    let row = ChallengeHistoryRow.make(week("2026-W44", done: [true, false, true]), locale: ruLocale, timeZone: msk, now: now)
    #expect(row.id == "2026-W44")
    #expect(plain(row.title) == "26 окт. – 1 нояб.", "диапазон дат недели, не ключ периода")
    #expect(row.detail == "2 из 3")
    #expect(!row.isMonth)
    #expect(row.completed == [YearText.title(.weekGoal5), YearText.title(.weekChars)])
}

/// Подпись недели — диапазон дат в локали интерфейса; год только у прошлых лет и недель на стыке годов.
@Test func weekTitleIsDateRangeInUserLocale() {
    let period = week("2026-W44", done: [true, true, false])
    #expect(plain(ChallengeHistoryRow.make(period, locale: ruLocale, timeZone: msk, now: now).title) == "26 окт. – 1 нояб.")
    let en = ChallengeHistoryRow.make(period, locale: Locale(identifier: "en_US"), timeZone: msk, now: now)
    #expect(plain(en.title) == "Oct 26 – Nov 1")
    #expect(!en.title.contains("W44") && !en.title.contains("2026"))
    // Прошлый год и стык годов (W01 2026: 29 дек. 2025 – 4 янв. 2026) — с годом.
    let past = ChallengeHistoryRow.make(week("2025-W44", done: [true, false, false]), locale: Locale(identifier: "en_US"),
                                        timeZone: msk, now: now)
    #expect(past.title.contains("2025") && !past.title.contains("W44"))
    let turn = ChallengeHistoryRow.make(week("2026-W01", done: [true, false, false]), locale: Locale(identifier: "en_US"),
                                        timeZone: msk, now: now)
    #expect(turn.title.contains("2025") && turn.title.contains("2026"))
}

@Test func monthRowShowsNameAndDate() {
    let month = ChallengePeriodResult(
        period: .month("2026-10"), parameters: parameters,
        results: [result(.monthGoal20, done: true, target: 20, at: at("2026-10-28 20:00"))], allDoneAt: nil)
    let row = ChallengeHistoryRow.make(month, locale: ruLocale, timeZone: msk, now: now)
    #expect(row.id == "2026-10")
    #expect(row.isMonth)
    #expect(row.title.lowercased().contains("октябр") && row.title.contains("2026"))
    #expect(row.detail.hasPrefix(YearText.title(.monthGoal20)))
    #expect(row.detail.contains("28") && row.detail.contains("2026"))
}

@Test func historyShowsEightPeriodsUntilShowAll() {
    let rows = (1...10).map { ChallengeHistoryRow.make(week(String(format: "2026-W%02d", $0), done: [true, false, false]),
                                                       locale: ruLocale, timeZone: msk, now: now) }
    #expect(ChallengeHistoryRow.limit == 8)
    #expect(ChallengeHistoryRow.visible(rows, showAll: false) == Array(rows.prefix(8)))
    #expect(ChallengeHistoryRow.visible(rows, showAll: true) == rows)
    #expect(ChallengeHistoryRow.hasMore(rows))
    #expect(!ChallengeHistoryRow.hasMore(Array(rows.prefix(8))))
    #expect(ChallengeHistoryRow.visible(Array(rows.prefix(3)), showAll: false).count == 3)
}

@MainActor @Test func historyRowsKeepTheStateOrder() throws {
    let periods = [week("2026-W45", done: [true, true, false]), week("2026-W44", done: [true, true, true])]
    let rows = ChallengeHistoryRow.rows(history: periods, locale: ruLocale, timeZone: msk, now: now)
    #expect(rows.map(\.id) == ["2026-W45", "2026-W44"])
    #expect(rows.map(\.detail) == ["2 из 3", "3 из 3"])
}

// MARK: - Ранг скорости

@Test func speedRankOfRecordIsFloorOfHundreds() {
    #expect(SpeedRank.of(cpm: 95) == .pedestrian && SpeedRank.of(cpm: 95).rawValue == 0)
    #expect(SpeedRank.of(cpm: 340) == .racer && SpeedRank.of(cpm: 340).rawValue == 3)
    let record = Record(value: 340, date: at("2026-11-02 20:00"), language: .ru)
    #expect(RecordsView.rankTitle(record) == YearText.title(.racer))
    #expect(RecordsView.rankTitle(Record(value: 95, date: .now, language: .en)) == YearText.title(.pedestrian))
    // Ранг не зависит от единицы: в WPM число рекорда другое, ранг тот же.
    #expect(SpeedUnit.wpm.wholeValue(340) == 68)
    #expect(RecordsView.rankTitle(record) == YearText.title(.racer))
}

@Test func speedRankHelpNamesEveryStep() {
    let text = HelpText.speedRank
    for rank in SpeedRank.allCases { #expect(text.contains(YearText.title(rank))) }
    #expect(text.contains("100"))
}

@Test func analyticsYearSymbolsExist() {
    for name in [RecordsView.rankIcon, ExperienceChartView.levelIcon, ChallengeHistoryRow.monthIcon,
                 ChallengeHistoryRow.weekIcon] {
        #expect(NSImage(systemSymbolName: name, accessibilityDescription: nil) != nil, "нет символа «\(name)»")
    }
}
