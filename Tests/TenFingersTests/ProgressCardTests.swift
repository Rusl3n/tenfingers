import Foundation
import SwiftData
import Testing
import TypingCore
@testable import TenFingers

/// Сервис с фиктивной целью и своим кэшем — без стандартного домена UserDefaults.
@MainActor func testAchievementService(_ context: ModelContext, now: Date) -> AchievementService {
    AchievementService(recorder: ResultRecorder(context: context, dayStartHour: 4), goalSeconds: { 600 },
                       now: { now }, cache: AchievementFactsCache())
}

private let monday = 2   // `Calendar.firstWeekday`: 1 — воскресенье, 2 — понедельник

private func day(_ seconds: Double, exercises: Int = 3) -> DayActivity {
    DayActivity(activeSeconds: seconds, completedExercises: exercises)
}

private func session(_ day: String, language: Language = .ru, chars: Int = 400, seconds: Double = 60,
                     accuracy: Double = 0.95, completed: Bool = true, hour: Int = 12) -> SessionSummary {
    let date = AnalyticsDates.date(day).map { $0.addingTimeInterval(Double(hour - 12) * 3600) } ?? .now
    return SessionSummary(day: day, endedAt: date, language: language, mode: .course, chars: chars,
                          activeSeconds: seconds, accuracy: accuracy, completed: completed)
}

// MARK: - Сетка месяца

/// Февраль 2028 (29 дней), неделя с понедельника: 1 февраля — вторник, значит пять недель и пустая первая клетка.
@Test func monthGridOfLeapFebruaryStartsOnTuesdayWithMondayFirst() {
    let grid = MonthGrid.make(today: "2028-02-15", statuses: [:], firstWeekday: monday)
    #expect(grid.year == 2028 && grid.month == 2 && grid.firstWeekday == monday)
    #expect(grid.weeks.count == 5)
    #expect(grid.weeks.allSatisfy { $0.count == 7 })
    #expect(grid.weeks[0][0] == nil)
    #expect(grid.weeks[0][1]?.day == 1 && grid.weeks[0][1]?.key == "2028-02-01")
    let days = grid.weeks.flatMap { $0 }.compactMap { $0 }
    #expect(days.map(\.day) == Array(1...29))
    // Последняя неделя: 28 (понедельник) и 29 февраля, дальше пусто.
    #expect(grid.weeks[4][0]?.day == 28 && grid.weeks[4][1]?.day == 29)
    #expect(grid.weeks[4][2...].allSatisfy { $0 == nil })
}

@Test func monthGridColumnsFollowFirstWeekday() {
    // Воскресенье первым: 1 февраля 2028 (вторник) — третья колонка.
    let sunday = MonthGrid.make(today: "2028-02-15", statuses: [:], firstWeekday: 1)
    #expect(sunday.weeks[0][0] == nil && sunday.weeks[0][1] == nil)
    #expect(sunday.weeks[0][2]?.day == 1)
    // Месяц, который начинается с первого дня недели: февраль 2027 (понедельник), ровно четыре недели.
    let exact = MonthGrid.make(today: "2027-02-10", statuses: [:], firstWeekday: monday)
    #expect(exact.weeks.count == 4)
    #expect(exact.weeks[0][0]?.day == 1)
}

@Test func monthGridMarksFutureDaysAndKeepsStatuses() {
    let statuses: [String: DayStatus] = ["2028-02-01": .full, "2028-02-02": .half, "2028-02-03": .frozen,
                                         "2028-02-04": DayStatus.none]
    let grid = MonthGrid.make(today: "2028-02-15", statuses: statuses, firstWeekday: monday)
    let cells = Dictionary(uniqueKeysWithValues: grid.weeks.flatMap { $0 }.compactMap { $0 }.map { ($0.day, $0) })
    #expect(cells[1]?.status == .full && cells[2]?.status == .half && cells[3]?.status == .frozen)
    #expect(cells[4]?.status == DayStatus.none && cells[5]?.status == DayStatus.none)
    #expect(cells[15]?.isFuture == false)
    #expect(cells[16]?.isFuture == true && cells[29]?.isFuture == true)
    #expect(cells[1]?.isFuture == false)
}

// MARK: - make

@Test func makeFillsStatusesIntoBothGridsAndSummary() {
    // 24–30 сентября семь полных дней (заработана заморозка); 1–3 октября: полный, половинный, полный;
    // 4-го пропуск (заморозка), 5-го полный; сегодня 5-е.
    var days: [String: DayActivity] = [
        "2026-10-01": day(700), "2026-10-02": day(200), "2026-10-03": day(700), "2026-10-05": day(700),
    ]
    for offset in 24...30 { days["2026-09-\(offset)"] = day(700) }
    let data = ProgressCardData.make(days: days, sessions: [], today: "2026-10-05", goalSeconds: 600,
                                     firstWeekday: monday)
    let summary = StreakCalculator.summarize(days: days, today: "2026-10-05", goalSeconds: 600)
    #expect(data.today == "2026-10-05")
    #expect(data.streak == summary.current && data.streak == 12)
    #expect(data.fullDays == summary.fullInCurrent && data.fullDays == 10)
    let month = Dictionary(uniqueKeysWithValues: data.monthGrid.weeks.flatMap { $0 }.compactMap { $0 }
        .map { ($0.key, $0.status) })
    #expect(month["2026-10-01"] == .full && month["2026-10-02"] == .half && month["2026-10-04"] == .frozen)
    let year = Dictionary(uniqueKeysWithValues: data.yearGrid.weeks.flatMap { $0 }.map { ($0.key, $0.status) })
    #expect(year["2026-10-01"] == .full && year["2026-10-02"] == .half && year["2026-10-04"] == .frozen)
    #expect(data.yearGrid.weeks.count == 53)
    #expect(data.yearGrid == ActivityCalendar.make(today: "2026-10-05", statuses: summary.statuses, firstWeekday: monday))
}

/// Заходил и цель: из `StreakSummary`. Три дня подряд — полный, половинный, полный: заходил 3 из 3, цель 1 (последний) из 2.
@Test func makeTakesVisitAndGoalCountsFromSummary() {
    let days: [String: DayActivity] = ["2026-10-01": day(700), "2026-10-02": day(200), "2026-10-03": day(700)]
    let data = ProgressCardData.make(days: days, sessions: [], today: "2026-10-03", goalSeconds: 600,
                                     firstWeekday: monday)
    #expect(data.visitCurrent == 3 && data.visitTotal == 3)
    #expect(data.goalCurrent == 1 && data.goalTotal == 2)
    let empty = ProgressCardData.make(days: [:], sessions: [], today: "2026-10-03", goalSeconds: 600, firstWeekday: monday)
    #expect(empty.visitCurrent == 0 && empty.visitTotal == 0 && empty.goalCurrent == 0 && empty.goalTotal == 0)
}

@Test func makeWithoutHistoryHasEmptyStatsAndPlainGrids() {
    let data = ProgressCardData.make(days: [:], sessions: [], today: "2026-10-24", goalSeconds: 600, firstWeekday: monday)
    #expect(data.streak == 0 && data.fullDays == 0)
    #expect(data.month == ProgressPeriodStats(seconds: 0, bestSpeed: nil, accuracy: nil))
    #expect(data.year == data.month && data.allTime == data.month)
    #expect(data.stats(.month) == data.month && data.stats(.year) == data.year && data.stats(.all) == data.allTime)
    #expect(data.monthGrid.weeks.flatMap { $0 }.compactMap { $0 }.allSatisfy { $0.status == DayStatus.none })
}

// MARK: - Время

/// Месяц считает дни с 1-го числа по сегодня, год — 53 недели сетки (с её первой клетки).
@Test func periodSecondsCountOnlyDaysOfThePeriod() {
    let today = "2026-10-24"
    let data0 = ProgressCardData.make(days: [:], sessions: [], today: today, goalSeconds: 600, firstWeekday: monday)
    let yearStart = data0.yearGrid.weeks[0][0].key
    let days: [String: DayActivity] = [
        "2026-09-30": day(1000),          // до месяца, в годе
        "2026-10-01": day(100),
        "2026-10-24": day(50),
        StreakCalculator.dayKey(yearStart, offset: -1): day(5000),   // до года
        yearStart: day(7),                // первый день года
    ]
    let data = ProgressCardData.make(days: days, sessions: [], today: today, goalSeconds: 600, firstWeekday: monday)
    #expect(data.month.seconds == 150)
    #expect(data.year.seconds == 1000 + 100 + 50 + 7)
}

// MARK: - Лучшая скорость

/// По правилу рекорда скорости: завершённое, без ошибок, проверка урока или текст от 300 знаков;
/// берётся максимум по языкам, вне периода — нет.
@Test func bestSpeedFollowsRecordRuleAndTakesMaxAcrossLanguages() {
    let today = "2026-10-24"
    let sessions = [
        session("2026-10-10", language: .ru, chars: 600, seconds: 120, accuracy: 1),            // 300 зн/мин
        session("2026-10-11", language: .en, chars: 900, seconds: 120, accuracy: 1),            // 450 зн/мин — лучшая
        session("2026-10-12", language: .ru, chars: 299, seconds: 10, accuracy: 1),             // 1794: короткое, не считается
        session("2026-10-13", language: .ru, chars: 1000, seconds: 30, accuracy: 1, completed: false),   // брошенное
        session("2026-10-14", language: .ru, chars: 1000, seconds: 30),                         // 2000, но с ошибками
        session("2026-09-20", language: .ru, chars: 3000, seconds: 60, accuracy: 1),            // вне месяца, в годе
    ]
    let data = ProgressCardData.make(days: [:], sessions: sessions, today: today, goalSeconds: 600, firstWeekday: monday)
    #expect(data.month.bestSpeed?.value == 450)
    #expect(data.month.bestSpeed?.language == .en)
    #expect(data.year.bestSpeed?.value == 3000)
    let onlyShort = ProgressCardData.make(days: [:], sessions: [session("2026-10-12", chars: 299, seconds: 10)],
                                          today: today, goalSeconds: 600, firstWeekday: monday)
    #expect(onlyShort.month.bestSpeed == nil && onlyShort.year.bestSpeed == nil)
}

private func lessonStep(_ day: String, kind: ExerciseKind, chars: Int = 90, seconds: Double = 24,
                        accuracy: Double = 1, errors: Int = 0) -> SessionSummary {
    SessionSummary(day: day, endedAt: AnalyticsDates.date(day) ?? .now, language: .ru, mode: .course, chars: chars,
                   activeSeconds: seconds, accuracy: accuracy, completed: true, lessonId: "l1", exerciseKind: kind,
                   errorCount: errors)
}

/// Проверка урока в 90 знаков без ошибок даёт лучшую скорость; с ошибкой, упражнение-тренировка и другой шаг — нет.
@Test func bestSpeedTakesCleanLessonCheckButNotDrillOrDirtyCheck() {
    let today = "2026-10-24"
    func best(_ sessions: [SessionSummary]) -> Record? {
        ProgressCardData.make(days: [:], sessions: sessions, today: today, goalSeconds: 600, firstWeekday: monday)
            .month.bestSpeed
    }
    let clean = best([lessonStep("2026-10-20", kind: .check, seconds: 90.0 * 60 / 224)])
    #expect(abs((clean?.value ?? 0) - 224) < 1e-9)
    #expect(best([lessonStep("2026-10-20", kind: .check, accuracy: 89.0 / 90, errors: 1)]) == nil)
    #expect(best([lessonStep("2026-10-20", kind: .drill)]) == nil)
    #expect(best([lessonStep("2026-10-20", kind: .words)]) == nil)
}

/// Нет подходящего упражнения: на карточке «пока нет» / "none yet", а не прочерк.
@Test func progressCardShowsNoneYetWithoutQualifyingExercise() {
    let data = ProgressCardData.make(days: [:], sessions: [lessonStep("2026-10-20", kind: .drill)], today: "2026-10-24",
                                     goalSeconds: 600, firstWeekday: monday)
    #expect(data.month.bestSpeed == nil)
    func speedValue(_ language: String, _ locale: Locale) -> String? {
        let bundle = Bundle(url: URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Localization/\(language).lproj"))!
        let text = ProgressCardText(data: data, period: .month, content: ProgressCardContent(), unit: .cpm,
                                    bundle: bundle, locale: locale)
        return text.metrics.first { $0.title == (language == "ru" ? "Лучшая скорость" : "Best speed") }?.value
    }
    #expect(speedValue("ru", Locale(identifier: "ru")) == "пока нет")
    #expect(speedValue("en", Locale(identifier: "en")) == "none yet")
}

// MARK: - Точность

@Test func accuracyIsWeightedByCharsAndSkipsAbandoned() {
    let today = "2026-10-24"
    let sessions = [
        session("2026-10-10", chars: 100, accuracy: 1.0),
        session("2026-10-11", chars: 300, accuracy: 0.9),
        session("2026-10-12", chars: 1000, accuracy: 0.1, completed: false),   // брошенное не считается
        session("2026-09-01", chars: 600, accuracy: 0.5),                       // вне месяца
    ]
    let data = ProgressCardData.make(days: [:], sessions: sessions, today: today, goalSeconds: 600, firstWeekday: monday)
    let month: Double = (100 * 1.0 + 300 * 0.9) / 400
    let year: Double = (100 * 1.0 + 300 * 0.9 + 600 * 0.5) / 1000
    let monthAccuracy: Double = data.month.accuracy ?? 0
    let yearAccuracy: Double = data.year.accuracy ?? 0
    #expect(abs(monthAccuracy - month) < 1e-9)
    #expect(abs(yearAccuracy - year) < 1e-9)
}

@Test func accuracyIsNilWithoutCompletedExercises() {
    let abandoned = [session("2026-10-10", chars: 500, accuracy: 0.8, completed: false)]
    let data = ProgressCardData.make(days: [:], sessions: abandoned, today: "2026-10-24", goalSeconds: 600,
                                     firstWeekday: monday)
    #expect(data.month.accuracy == nil && data.year.accuracy == nil)
    let zeroChars = ProgressCardData.make(days: [:], sessions: [session("2026-10-10", chars: 0)], today: "2026-10-24",
                                          goalSeconds: 600, firstWeekday: monday)
    #expect(zeroChars.month.accuracy == nil)
}

// MARK: - Период и загрузка

@Test func progressPeriodTitlesAndOrder() {
    #expect(ProgressPeriod.allCases == [.month, .year, .all])
    #expect(ProgressPeriod.month.title == "Этот месяц")
    #expect(ProgressPeriod.year.title == "Год")
    #expect(ProgressPeriod.all.title == "Без календаря" && ProgressPeriod.all.rawValue == "all")
    #expect(ProgressPeriod(rawValue: "month") == .month && ProgressPeriod(rawValue: "all") == .all)
    #expect(ProgressPeriod(rawValue: "nonsense") == nil)
}

@MainActor @Test func loaderReadsDaysAndSessionsFromStore() throws {
    let container = try ModelStore.makeContainer(inMemory: true)
    let context = container.mainContext
    let now = Date(timeIntervalSince1970: 1_792_843_200)   // 24 октября 2026 г., 12:00 UTC
    let today = LogicalDay.key(for: now, dayStartHour: 4)
    let record = DayRecord(logicalDay: today)
    record.activeSeconds = 700
    record.completedExercises = 4
    context.insert(record)
    try context.save()
    let data = try ProgressCardLoader.load(context: context, now: now, goalSeconds: 600, dayStartHour: 4,
                                           firstWeekday: monday,
                                           service: testAchievementService(context, now: now))
    #expect(data.today == today)
    #expect(data.streak == 1 && data.fullDays == 1)
    #expect(data.month.seconds == 700)
    #expect(data.monthGrid.weeks.flatMap { $0 }.compactMap { $0 }.first { $0.key == today }?.status == .full)
}

// MARK: - Без календаря: всё время

/// «Без календаря» считает показатели за всё время, в том числе сессии и дни старше года.
@Test func allTimeStatsCoverSessionsAndDaysOlderThanAYear() {
    let today = "2026-10-24"
    let days: [String: DayActivity] = ["2026-10-24": day(50), "2025-01-05": day(5000), "2020-03-01": day(700)]
    let sessions = [
        session("2026-10-10", chars: 600, seconds: 120, accuracy: 1.0),                // 300 зн/мин
        session("2024-05-05", chars: 1800, seconds: 120, accuracy: 1.0),               // 900 зн/мин, старше года
        session("2024-05-06", chars: 900, seconds: 60, accuracy: 0.9, completed: false), // брошенное
    ]
    let data = ProgressCardData.make(days: days, sessions: sessions, today: today, goalSeconds: 600, firstWeekday: monday)
    #expect(data.allTime.seconds == 5750)
    #expect(data.allTime.bestSpeed?.value == 900)
    let expected: Double = 1.0
    #expect(abs((data.allTime.accuracy ?? 0) - expected) < 1e-9)
    // Год и месяц старые данные не видят.
    #expect(data.year.seconds == 50 && data.month.seconds == 50)
    #expect(data.year.bestSpeed?.value == 300)
    #expect(data.stats(.all) == data.allTime)
}

@MainActor @Test func loaderReadsHistoryOlderThanTheYearGrid() throws {
    let container = try ModelStore.makeContainer(inMemory: true)
    let context = container.mainContext
    let now = Date(timeIntervalSince1970: 1_792_843_200)   // 24 октября 2026 г.
    let old = DayRecord(logicalDay: "2022-02-02")
    old.activeSeconds = 900
    old.completedExercises = 3
    context.insert(old)
    let ended = AnalyticsDates.date("2022-02-02") ?? now
    context.insert(SessionRecord(mode: "course", language: "ru", lessonId: nil, startedAt: ended, endedAt: ended,
                                 logicalDay: "2022-02-02", activeSeconds: 100, chars: 500, errorCount: 0, cpm: 300,
                                 accuracy: 1, completed: true, hintLevel: "off", maxErrorStreak: 0,
                                 wrongKeystrokes: 0))
    try context.save()
    let data = try ProgressCardLoader.load(context: context, now: now, goalSeconds: 600, dayStartHour: 4,
                                           firstWeekday: monday,
                                           service: testAchievementService(context, now: now))
    #expect(data.year.seconds == 0 && data.year.bestSpeed == nil)
    #expect(data.allTime.seconds == 900)
    #expect(data.allTime.bestSpeed?.value == 300)
    #expect(data.allTime.accuracy == 1)
}

// MARK: - Сетка месяца: крайние случаи

/// Месяц в шесть строк: 31 день, а первое число приходится на последнюю колонку недели.
@Test func monthGridWithSixRows() {
    // Март 2025: 1-е — суббота. С воскресенья суббота — последняя (7-я) колонка: 6 + 31 = 37 клеток → 6 строк.
    let grid = MonthGrid.make(today: "2025-03-15", statuses: [:], firstWeekday: 1)
    #expect(grid.weeks.count == 6)
    #expect(grid.weeks[0][0..<6].allSatisfy { $0 == nil } && grid.weeks[0][6]?.day == 1)
    #expect(grid.weeks.allSatisfy { $0.count == 7 })
    #expect(grid.weeks.flatMap { $0 }.compactMap { $0 }.map(\.day) == Array(1...31))
    #expect(grid.weeks[5][0]?.day == 30 && grid.weeks[5][1]?.day == 31 && grid.weeks[5][2...].allSatisfy { $0 == nil })
}

@Test func monthGridAtYearBoundaries() {
    let december = MonthGrid.make(today: "2026-12-31", statuses: ["2026-12-31": .full], firstWeekday: monday)
    #expect(december.year == 2026 && december.month == 12)
    let lastDay = december.weeks.flatMap { $0 }.compactMap { $0 }.last
    #expect(lastDay?.day == 31 && lastDay?.status == .full && lastDay?.isFuture == false)
    let january = MonthGrid.make(today: "2027-01-01", statuses: ["2026-12-31": .full], firstWeekday: monday)
    #expect(january.year == 2027 && january.month == 1)
    let cells = january.weeks.flatMap { $0 }.compactMap { $0 }
    #expect(cells.count == 31 && cells.first?.key == "2027-01-01" && cells.first?.isFuture == false)
    #expect(cells.dropFirst().allSatisfy { $0.isFuture })
    #expect(cells.allSatisfy { $0.key.hasPrefix("2027-01-") })   // декабрьский статус в январь не попадает
    // 1 января 2027 — пятница: при неделе с понедельника в первой строке четыре пустые клетки.
    #expect(january.weeks[0][0..<4].allSatisfy { $0 == nil } && january.weeks[0][4]?.day == 1)
}

/// Сессия в 02:00 при начале дня в 4 утра относится к предыдущему логическому дню: «сегодня» карточки — вчерашнее число.
@MainActor @Test func loaderPutsNightSessionIntoPreviousLogicalDay() throws {
    let container = try ModelStore.makeContainer(inMemory: true)
    let context = container.mainContext
    var calendar = Calendar.current
    calendar.timeZone = .current
    let now = try #require(calendar.date(from: DateComponents(year: 2026, month: 10, day: 24, hour: 2)))
    let logical = LogicalDay.key(for: now, dayStartHour: 4)
    #expect(logical == "2026-10-23")
    let record = DayRecord(logicalDay: logical)
    record.activeSeconds = 700
    record.completedExercises = 4
    context.insert(record)
    context.insert(SessionRecord(mode: "course", language: "ru", lessonId: nil, startedAt: now.addingTimeInterval(-120),
                                 endedAt: now, logicalDay: logical, activeSeconds: 120, chars: 600, errorCount: 0,
                                 cpm: 300, accuracy: 1, completed: true, hintLevel: "off", maxErrorStreak: 0,
                                 wrongKeystrokes: 0))
    try context.save()
    let data = try ProgressCardLoader.load(context: context, now: now, goalSeconds: 600, dayStartHour: 4,
                                           firstWeekday: monday,
                                           service: testAchievementService(context, now: now))
    #expect(data.today == "2026-10-23")
    #expect(data.monthGrid.weeks.flatMap { $0 }.compactMap { $0 }.first { $0.key == "2026-10-23" }?.isFuture == false)
    #expect(data.monthGrid.weeks.flatMap { $0 }.compactMap { $0 }.first { $0.key == "2026-10-24" }?.isFuture == true)
    #expect(data.streak == 1 && data.month.seconds == 700 && data.month.bestSpeed?.value == 300)
    // Тот же момент при начале дня в полночь — уже 24 октября.
    #expect(LogicalDay.key(for: now, dayStartHour: 0) == "2026-10-24")
}

// MARK: - Содержимое

@Test func progressContentDefaultsAndEmptiness() {
    let content = ProgressCardContent()
    #expect(content.showsStreak && content.showsFullDays && content.showsTime && content.showsSpeed && content.showsAccuracy)
    #expect(content.showsVisits && content.showsGoalDays)
    #expect(!content.isEmpty && content.showsMetrics)
    var none = ProgressCardContent(showsStreak: false, showsFullDays: false, showsTime: false, showsSpeed: false,
                                   showsAccuracy: false, showsVisits: false, showsGoalDays: false)
    #expect(none.isEmpty && !none.showsMetrics)
    none.showsAccuracy = true
    #expect(!none.isEmpty && none.showsMetrics)
    none.showsAccuracy = false
    none.showsVisits = true
    #expect(!none.isEmpty && !none.showsMetrics)
    none.showsVisits = false
    none.showsGoalDays = true
    #expect(!none.isEmpty && !none.showsMetrics)
    var flameOnly = ProgressCardContent(showsStreak: true, showsFullDays: false, showsTime: false, showsSpeed: false,
                                        showsAccuracy: false, showsVisits: false, showsGoalDays: false)
    #expect(!flameOnly.isEmpty && !flameOnly.showsMetrics)
    flameOnly.showsStreak = false
    #expect(flameOnly.isEmpty)
}

@Test func progressContentIsRememberedInDefaults() {
    let (defaults, name) = makeTestDefaults("progress-content-")
    defer { removeTestDefaults(name) }
    #expect(ProgressCardContent.load(from: defaults) == ProgressCardContent())
    var content = ProgressCardContent()
    content.showsStreak = false
    content.showsSpeed = false
    content.showsVisits = false
    content.save(to: defaults)
    #expect(defaults.object(forKey: "shareProgressShowStreak") as? Bool == false)
    #expect(defaults.object(forKey: "shareProgressShowFullDays") as? Bool == true)
    #expect(defaults.object(forKey: "shareProgressShowTime") as? Bool == true)
    #expect(defaults.object(forKey: "shareProgressShowSpeed") as? Bool == false)
    #expect(defaults.object(forKey: "shareProgressShowAccuracy") as? Bool == true)
    #expect(defaults.object(forKey: "shareProgressShowVisits") as? Bool == false)
    #expect(defaults.object(forKey: "shareProgressShowGoalDays") as? Bool == true)
    #expect(ProgressCardContent.load(from: defaults) == content)
    #expect(SettingsKey.shareProgressShowStreak == "shareProgressShowStreak")
    #expect(SettingsKey.shareProgressShowFullDays == "shareProgressShowFullDays")
    #expect(SettingsKey.shareProgressShowTime == "shareProgressShowTime")
    #expect(SettingsKey.shareProgressShowSpeed == "shareProgressShowSpeed")
    #expect(SettingsKey.shareProgressShowAccuracy == "shareProgressShowAccuracy")
    #expect(SettingsKey.shareProgressShowVisits == "shareProgressShowVisits")
    #expect(SettingsKey.shareProgressShowGoalDays == "shareProgressShowGoalDays")
}

/// Кнопки листа неактивны, когда не показано ничего: все переключатели выключены и нет календаря.
@Test func nothingToShowOnlyWithoutContentAndCalendar() {
    let off = ProgressCardContent(showsStreak: false, showsFullDays: false, showsTime: false, showsSpeed: false,
                                  showsAccuracy: false, showsVisits: false, showsGoalDays: false)
    func options(_ content: ProgressCardContent, _ period: ProgressPeriod) -> ShareOptions {
        var options = ShareOptions(signature: .none, theme: .light, background: .colored, format: .wide)
        options.progressContent = content
        options.progressPeriod = period
        return options
    }
    let progress = ShareEvent.progress(ProgressCardData.make(days: [:], sessions: [], today: "2026-10-24",
                                                             goalSeconds: 600, firstWeekday: monday))
    #expect(options(off, .all).hasNothingToShow(for: progress))
    #expect(!options(off, .month).hasNothingToShow(for: progress))
    #expect(!options(off, .year).hasNothingToShow(for: progress))
    #expect(!options(ProgressCardContent(), .all).hasNothingToShow(for: progress))
    // У других карточек содержимое «Мой прогресс» не при чём.
    #expect(!options(off, .all).hasNothingToShow(for: .streak(days: 3, full: 2)))
}

// MARK: - Общая карточка для главной и аналитики

@MainActor @Test func progressCardFactoryLoadsFreshData() throws {
    let container = try ModelStore.makeContainer(inMemory: true)
    let context = container.mainContext
    let now = Date(timeIntervalSince1970: 1_792_843_200)
    let record = DayRecord(logicalDay: LogicalDay.key(for: now, dayStartHour: 4))
    record.activeSeconds = 700
    record.completedExercises = 4
    context.insert(record)
    try context.save()
    let card = try ShareCard.progress(context: context, goalSeconds: 600, dayStartHour: 4, now: now)
    guard case .progress(let data) = card.event else {
        Issue.record("карточка прогресса")
        return
    }
    #expect(data.streak == 1 && data.month.seconds == 700)
    #expect(card.date == now)
}

// MARK: - Аналитика

/// Кнопка «Поделиться» в календаре аналитики видна, только если есть история (как на главной).
@MainActor @Test func analyticsShareNeedsHistory() throws {
    let container = try ModelStore.makeContainer(inMemory: true)
    let context = container.mainContext
    let empty = try AnalyticsLoader(context: context).summary(language: .ru, courses: [:], today: "2026-10-24",
                                                              goalSeconds: 600, firstWeekday: monday)
    #expect(!AnalyticsContent.canShareProgress(empty))
    let ended = Date(timeIntervalSince1970: 1_792_843_200)
    context.insert(SessionRecord(mode: "course", language: "ru", lessonId: nil, startedAt: ended, endedAt: ended,
                                 logicalDay: "2026-10-24", activeSeconds: 60, chars: 100, errorCount: 0, cpm: 100,
                                 accuracy: 1, completed: true, hintLevel: "off", maxErrorStreak: 0, wrongKeystrokes: 0))
    try context.save()
    let filled = try AnalyticsLoader(context: context).summary(language: .ru, courses: [:], today: "2026-10-24",
                                                               goalSeconds: 600, firstWeekday: monday)
    #expect(AnalyticsContent.canShareProgress(filled))
}

// MARK: - Уровень на карточке (фаза 8, §5)

@MainActor @Test func progressCardCarriesTheLevelFromTheGivenSource() throws {
    let container = try ModelStore.makeContainer(inMemory: true)
    let context = container.mainContext
    let now = Date(timeIntervalSince1970: 1_792_843_200)
    let ended = now.addingTimeInterval(-3600)
    for _ in 0..<12 {
        context.insert(SessionRecord(mode: "course", language: "ru", lessonId: nil, startedAt: ended.addingTimeInterval(-600),
                                     endedAt: ended, logicalDay: "2026-10-24", activeSeconds: 600, chars: 300,
                                     errorCount: 0, cpm: 150, accuracy: 1, completed: true, hintLevel: "off",
                                     maxErrorStreak: 0, wrongKeystrokes: 0))
    }
    try context.save()
    let service = testAchievementService(context, now: now)
    let expected = LevelCurve.progress(forExperience: Experience.ledger(try service.facts()).total).level
    let data = try ProgressCardLoader.load(context: context, now: now, goalSeconds: 600, dayStartHour: 4,
                                           service: service)
    #expect(expected > 1)
    #expect(data.level == expected)
    #expect(data.level == (try YearLoader(context: context, service: service).state().level))
}

@Test func progressCardTextHasLevelLineUnderTheSignature() throws {
    let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().appendingPathComponent("Localization/en.lproj")
    let en = try #require(Bundle(url: url))
    let base = ProgressCardData.make(days: [:], sessions: [], today: "2026-10-24", goalSeconds: 600,
                                     firstWeekday: monday, level: 7)
    let options = ShareOptions(signature: .none, theme: .light, background: .colored, format: .wide)
    let text = ShareCardText(card: ShareCard(.progress(base)), options: options,
                             profile: ShareProfile(nickname: "Ann", fullName: ""), unit: .cpm, bundle: en,
                             locale: Locale(identifier: "en"))
    #expect(text.levelLine == "Level 7")
    let none = ProgressCardData.make(days: [:], sessions: [], today: "2026-10-24", goalSeconds: 600, firstWeekday: monday)
    let plain = ShareCardText(card: ShareCard(.progress(none)), options: options,
                              profile: ShareProfile(nickname: "Ann", fullName: ""), unit: .cpm, bundle: en,
                              locale: Locale(identifier: "en"))
    #expect(plain.levelLine == nil)
    // У других карточек строки уровня нет.
    let streak = ShareCardText(card: ShareCard(.streak(days: 3, full: 2)), options: options,
                               profile: ShareProfile(nickname: "Ann", fullName: ""), unit: .cpm, bundle: en,
                               locale: Locale(identifier: "en"))
    #expect(streak.levelLine == nil)
}
