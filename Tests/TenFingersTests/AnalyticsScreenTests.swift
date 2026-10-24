import AppKit
import Foundation
import SwiftData
import Testing
import TypingCore
@testable import TenFingers

private func utc() -> Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    return calendar
}

/// 2026-03-10 12:00 UTC (вторник).
private let noon = Date(timeIntervalSince1970: 1_773_144_000)

// MARK: - Меню

@Test func sidebarHasAnalyticsBeforeSettings() {
    #expect(SidebarItem.allCases == [.home, .course, .training, .practice, .analytics, .achievements, .settings])
    #expect(SidebarItem.analytics.icon == "chart.xyaxis.line")
}

// MARK: - Период графиков

@Test func periodStartsAtFirstDayOfWindow() {
    #expect(AnalyticsPeriod.month.startDay(today: "2026-03-10") == "2026-02-09")
    #expect(AnalyticsPeriod.quarter.startDay(today: "2026-03-10") == "2025-12-11")
    #expect(AnalyticsPeriod.all.startDay(today: "2026-03-10") == nil)
    #expect(AnalyticsPeriod.allCases == [.month, .quarter, .all])
}

// MARK: - Графики

@Test func chartSkipsDaysWithoutCompletedExercisesAndHasTrend() throws {
    let daily = [
        DailyPoint(day: "2026-03-01", cpm: 100, accuracy: 0.9, seconds: 60, sessions: 1),
        DailyPoint(day: "2026-03-02", cpm: 0, accuracy: 0, seconds: 30, sessions: 0),
        DailyPoint(day: "2026-03-03", cpm: 200, accuracy: 0.95, seconds: 60, sessions: 2),
        DailyPoint(day: "2026-03-04", cpm: 300, accuracy: 0.97, seconds: 60, sessions: 1),
    ]
    let chart = ChartSeries.make(daily, calendar: utc())
    #expect(chart.points.map(\.day) == ["2026-03-01", "2026-03-03", "2026-03-04"])
    #expect(chart.points.map(\.cpm) == [100, 200, 300])
    #expect(chart.points.map(\.accuracy) == [0.9, 0.95, 0.97])
    #expect(chart.hasEnoughData)
    let trend = try #require(chart.trend)
    #expect(abs(trend.startCpm - 100) < 0.001)
    #expect(abs(trend.endCpm - 300) < 0.001)
    // Точка дня — полдень этого дня.
    #expect(utc().dateComponents([.year, .month, .day, .hour], from: chart.points[0].date)
            == DateComponents(year: 2026, month: 3, day: 1, hour: 12))
}

@Test func chartWithOnePointIsNotEnough() {
    let chart = ChartSeries.make([DailyPoint(day: "2026-03-01", cpm: 100, accuracy: 0.9, seconds: 60, sessions: 1)],
                                 calendar: utc())
    #expect(!chart.hasEnoughData)
    #expect(chart.trend == nil)
    #expect(!ChartSeries.make([], calendar: utc()).hasEnoughData)
}

@Test func speedUnitConvertsChartValues() {
    #expect(SpeedUnit.cpm.value(250) == 250)
    #expect(SpeedUnit.wpm.value(250) == 50)
}

// MARK: - Тепловая карта

@Test func heatmapMergesCaseRowsByKeyCode() {
    let entries = [
        KeyStatEntry(character: "а", stat: KeyStatSummary(keyCode: 3, presses: 90, errors: 9, ewmaMs: 200)),
        KeyStatEntry(character: "А", stat: KeyStatSummary(keyCode: 3, presses: 10, errors: 1, ewmaMs: 400)),
        KeyStatEntry(character: "о", stat: KeyStatSummary(keyCode: 38, presses: 50, errors: 0, ewmaMs: nil)),
    ]
    let keys = HeatmapModel.merge(entries)
    #expect(keys.map(\.keyCode) == [3, 38])
    let a = keys[0]
    #expect(a.label == "а")
    #expect(a.stat.presses == 100)
    #expect(a.stat.errors == 10)
    #expect(abs((a.stat.ewmaMs ?? 0) - 220) < 0.001)   // (200 × 90 + 400 × 10) / 100
    #expect(keys[1].stat.ewmaMs == nil)
}

@Test func heatmapValuesFollowMode() {
    let keys = HeatmapModel.merge([
        KeyStatEntry(character: "а", stat: KeyStatSummary(keyCode: 3, presses: 100, errors: 10, ewmaMs: 300)),
        KeyStatEntry(character: "о", stat: KeyStatSummary(keyCode: 38, presses: 100, errors: 0, ewmaMs: 150)),
        KeyStatEntry(character: "ы", stat: KeyStatSummary(keyCode: 1, presses: 2, errors: 2, ewmaMs: nil)),
    ])
    let errors = HeatmapModel.heat(keys, mode: .errors)
    #expect(errors[3] == 1)
    #expect(errors[38] == 0)
    #expect(errors[1] == nil)   // мало нажатий
    let slow = HeatmapModel.heat(keys, mode: .slowness)
    #expect(slow[3] == 1)
    #expect(slow[38] == 0)
    #expect(slow[1] == nil)     // нет замера
}

@Test func heatmapHelpTextNamesLetterPressesErrorsAndTime() {
    let key = HeatmapModel.merge([
        KeyStatEntry(character: "ф", stat: KeyStatSummary(keyCode: 0, presses: 120, errors: 6, ewmaMs: 210.4)),
    ])[0]
    let text = key.helpText(locale: Locale(identifier: "ru_RU"))
    #expect(text.contains("ф"))
    #expect(text.contains("120"))
    #expect(text.contains("5,0%"))
    #expect(text.contains("210"))
}

// MARK: - Пальцы

@Test func fingerRowsListAllFingersWithThumbsLast() {
    let keys = HeatmapModel.merge([
        KeyStatEntry(character: "ф", stat: KeyStatSummary(keyCode: 0, presses: 100, errors: 10, ewmaMs: 300)),  // левый мизинец
        KeyStatEntry(character: "а", stat: KeyStatSummary(keyCode: 3, presses: 100, errors: 5, ewmaMs: 200)),   // левый указательный
    ])
    let rows = FingerRow.rows(keys)
    #expect(rows.map(\.finger) == [.leftPinky, .leftRing, .leftMiddle, .leftIndex,
                                   .rightIndex, .rightMiddle, .rightRing, .rightPinky, .thumb])
    #expect(rows[0].presses == 100)
    #expect(abs(rows[0].errorRate - 0.1) < 0.0001)
    #expect(rows[0].averageMs == 300)
    #expect(rows[1].presses == 0)
    #expect(rows[1].averageMs == nil)
    // Полоса — доля ошибок относительно худшего пальца.
    #expect(rows[0].barFraction == 1)
    #expect(abs(rows[3].barFraction - 0.5) < 0.0001)
    #expect(rows[1].barFraction == 0)
}

// MARK: - Календарь

@Test func calendarHas53WeeksEndingWithTodaysWeek() {
    // 2026-03-10 — вторник; неделя с понедельника.
    let calendar = ActivityCalendar.make(today: "2026-03-10", statuses: ["2026-03-09": .full, "2026-03-08": .frozen],
                                         firstWeekday: 2)
    #expect(calendar.weeks.count == 53)
    #expect(calendar.weeks.allSatisfy { $0.count == 7 })
    let last = calendar.weeks[52]
    #expect(last.map(\.key) == ["2026-03-09", "2026-03-10", "2026-03-11", "2026-03-12",
                                "2026-03-13", "2026-03-14", "2026-03-15"])
    #expect(last[0].status == .full)
    #expect(last[1].status == DayStatus.none)
    #expect(!last[1].isFuture)
    #expect(last[2].isFuture)
    #expect(calendar.weeks[51][6].key == "2026-03-08")
    #expect(calendar.weeks[51][6].status == .frozen)
    #expect(calendar.weeks[0][0].key == StreakCalculator.dayKey("2026-03-09", offset: -52 * 7))
}

@Test func calendarStartsWeeksOnSundayWhenRegionSaysSo() {
    let calendar = ActivityCalendar.make(today: "2026-03-10", statuses: [:], firstWeekday: 1)
    #expect(calendar.weeks[52][0].key == "2026-03-08")
    #expect(calendar.weeks[52][2].key == "2026-03-10")
}

@Test func calendarLabelsMonthsWhereTheyStart() {
    let calendar = ActivityCalendar.make(today: "2026-03-10", statuses: [:], firstWeekday: 2)
    // Последняя колонка начинается 9 марта, предыдущие — 2 марта и 23 февраля.
    #expect(calendar.monthLabels.last == ActivityCalendar.MonthLabel(column: 51, month: 3))
    #expect(calendar.monthLabels.allSatisfy { (1...12).contains($0.month) })
    let columns = calendar.monthLabels.map(\.column)
    #expect(columns == columns.sorted())
    #expect(zip(columns, columns.dropFirst()).allSatisfy { $1 - $0 >= 3 })
}

// MARK: - История

@Test func historyNamesModesAndSources() throws {
    #expect(SessionHistory.modeTitle("course") == "Урок")
    #expect(SessionHistory.modeTitle("adaptive") == "Тренировка")
    #expect(SessionHistory.modeTitle("weak") == "Слабые места")
    #expect(SessionHistory.modeTitle("practice") == "Практика")
    #expect(SessionHistory.modeTitle("future") == "future")

    let texts = try TextLibrary.load(.ru)
    let text = try #require(texts.first)
    func title(_ source: String?) -> String? {
        SessionHistory.sourceTitle(source, library: texts)
    }
    #expect(title("words") == "Частотные слова")
    #expect(title("symbols") == "Цифры и символы")
    #expect(title("custom") == "Свой текст")
    #expect(title("library:\(text.id)") == text.title)
    #expect(title("library:missing") == nil)
    #expect(title("adaptive") == nil)
    #expect(title(nil) == nil)
}

// MARK: - Подсказка в карточке рекордов

@MainActor @Test func recordsHintShowsOnlyWhileThereAreNoRecords() {
    let none = Records(bestCpm: [:], bestAccuracy: [:], longestStreak: 3)
    #expect(RecordsView.showsEmptyHint(none))
    let record = Record(value: 200, date: noon, language: .ru)
    #expect(!RecordsView.showsEmptyHint(Records(bestCpm: [.ru: record], bestAccuracy: [:], longestStreak: 0)))
    #expect(!RecordsView.showsEmptyHint(Records(bestCpm: [:], bestAccuracy: [.en: record], longestStreak: 0)))
}

// MARK: - Прогресс курса

@Test func courseProgressCountsPassedLessonsAndHistoryStars() throws {
    let course = try CourseCatalog.load(.ru)
    let lessons = course.lessons
    let check = SessionSummary(day: "2026-03-10", endedAt: noon, language: .ru, mode: .course, chars: 200,
                               activeSeconds: 60, accuracy: 0.97, completed: true,
                               lessonId: lessons[0].id, exerciseKind: .check, cpm: 10)
    let row = CourseProgressRow.make(
        course: course,
        lessons: [StoredLesson(lessonId: lessons[0].id, passed: true, storedStars: 3),   // история важнее: 1 звезда
                  StoredLesson(lessonId: lessons[1].id, passed: true, storedStars: 2)],  // проверок нет — из базы: 2 → ★★★
        sessions: [check])
    #expect(row.language == .ru)
    #expect(row.passed == 2)
    #expect(row.total == lessons.count)
    #expect(row.stars == 4)
    #expect(row.maxStars == lessons.count * 5)
    #expect(abs(row.fraction - 2 / Double(lessons.count)) < 0.0001)
}

@Test func courseProgressStarsOfPassedLessonWithoutHistoryAreAtLeastOneLikeOnTheMap() throws {
    let course = try CourseCatalog.load(.ru)
    let lesson = course.lessons[0]
    let row = CourseProgressRow.make(course: course,
                                     lessons: [StoredLesson(lessonId: lesson.id, passed: true, storedStars: 0)],
                                     sessions: [])
    #expect(row.stars == 1)
    #expect(row.stars == LessonOverview.make(lessonId: lesson.id, targetCpm: course.stages[0].targetCpm, sessions: [],
                                              storedStars: 0, isPassed: true).stars)
}

// MARK: - Чтение из базы

@MainActor
private func makeContainer() throws -> ModelContainer {
    try ModelStore.makeContainer(inMemory: true)
}

private func session(day: String, language: Language = .ru, mode: ExerciseMode = .course, chars: Int = 100,
                     seconds: Double = 60, accuracy: Double = 0.95, completed: Bool = true,
                     endedAt: Date = noon, lessonId: String? = nil, kind: ExerciseKind? = nil,
                     source: String? = nil) -> SessionRecord {
    SessionRecord(mode: mode.rawValue, language: language.rawValue, lessonId: lessonId,
                  startedAt: endedAt.addingTimeInterval(-seconds), endedAt: endedAt, logicalDay: day,
                  activeSeconds: seconds, chars: chars, errorCount: 0, cpm: Double(chars) / seconds * 60,
                  accuracy: accuracy, completed: completed, hintLevel: "full", maxErrorStreak: 0,
                  wrongKeystrokes: 0, exerciseKind: kind?.rawValue, source: source)
}

@MainActor @Test func loaderChartUsesOnlyLanguageAndPeriod() throws {
    let container = try makeContainer()
    let context = container.mainContext
    context.insert(session(day: "2026-03-10", chars: 200))                    // 200 зн/мин
    context.insert(session(day: "2026-02-20", chars: 100))                    // 100 зн/мин
    context.insert(session(day: "2026-01-01", chars: 600))                    // вне 30 дней
    context.insert(session(day: "2026-03-10", language: .en, chars: 900))     // другой язык
    try context.save()
    let loader = AnalyticsLoader(context: context)
    let month = try loader.chart(language: .ru, period: .month, today: "2026-03-10", calendar: utc())
    #expect(month.points.map(\.day) == ["2026-02-20", "2026-03-10"])
    #expect(month.points.map(\.cpm) == [100, 200])
    let all = try loader.chart(language: .ru, period: .all, today: "2026-03-10", calendar: utc())
    #expect(all.points.map(\.day) == ["2026-01-01", "2026-02-20", "2026-03-10"])
}

@MainActor @Test func loaderHistoryIsNewestFirstAndLimited() throws {
    let container = try makeContainer()
    let context = container.mainContext
    for index in 0..<(SessionHistory.limit + 5) {
        context.insert(session(day: "2026-03-10", endedAt: noon.addingTimeInterval(Double(index))))
    }
    try context.save()
    let rows = try AnalyticsLoader(context: context).history(courses: [:], texts: [:])
    #expect(rows.count == SessionHistory.limit)
    #expect(rows.first?.endedAt == noon.addingTimeInterval(Double(SessionHistory.limit + 4)))
    #expect(zip(rows, rows.dropFirst()).allSatisfy { $0.endedAt > $1.endedAt })
}

@MainActor @Test func loaderHistoryRowCarriesLessonTitleAndAbandonedMark() throws {
    let container = try makeContainer()
    let context = container.mainContext
    let course = try CourseCatalog.load(.ru)
    let lesson = course.lessons[0]
    context.insert(session(day: "2026-03-10", completed: false, lessonId: lesson.id, kind: .words))
    context.insert(session(day: "2026-03-10", mode: .practice, endedAt: noon.addingTimeInterval(-10), source: "words"))
    try context.save()
    let rows = try AnalyticsLoader(context: context).history(courses: [.ru: course], texts: [:])
    #expect(rows.count == 2)
    #expect(rows[0].modeTitle == "Урок")
    #expect(rows[0].title?.contains(lesson.localizedTitle) == true)
    #expect(rows[0].abandoned)
    #expect(rows[0].language == .ru)
    #expect(rows[1].modeTitle == "Практика")
    #expect(rows[1].title == "Частотные слова")
    #expect(!rows[1].abandoned)
}

/// Лучшая скорость: чистая проверка урока в 90 знаков (224 зн/мин) — рекорд; та же с ошибкой, тренировка и шаг «слова» — нет;
/// рекорд точности остаётся только от 300 знаков.
@MainActor @Test func loaderRecordsTakeCleanLessonChecksForSpeedOnly() throws {
    let container = try makeContainer()
    let context = container.mainContext
    let seconds = 90.0 * 60 / 224
    context.insert(session(day: "2026-03-09", chars: 90, seconds: seconds, accuracy: 1, endedAt: noon,
                           lessonId: "l1", kind: .check))
    let dirty = session(day: "2026-03-09", chars: 90, seconds: 10, accuracy: 89.0 / 90, endedAt: noon.addingTimeInterval(1),
                        lessonId: "l1", kind: .check)
    dirty.errorCount = 1
    context.insert(dirty)
    context.insert(session(day: "2026-03-09", chars: 90, seconds: 10, accuracy: 1, endedAt: noon.addingTimeInterval(2),
                           lessonId: "l1", kind: .drill))
    context.insert(session(day: "2026-03-09", chars: 90, seconds: 10, accuracy: 1, endedAt: noon.addingTimeInterval(3),
                           lessonId: "l1", kind: .words))
    try context.save()
    let data = try AnalyticsLoader(context: context).summary(
        language: .ru, courses: [:], today: "2026-03-10", goalSeconds: 600, firstWeekday: 2)
    #expect(abs((data.records.bestCpm[.ru]?.value ?? 0) - 224) < 1e-9)
    #expect(data.records.bestAccuracy.isEmpty)
}

@MainActor @Test func loaderSummaryHasTotalsDatesRecordsAndCalendar() throws {
    let container = try makeContainer()
    let context = container.mainContext
    let day = DayRecord(logicalDay: "2026-03-09")
    day.activeSeconds = 700
    day.completedExercises = 2
    context.insert(day)
    let today = DayRecord(logicalDay: "2026-03-10")
    today.activeSeconds = 100
    today.completedExercises = 1
    context.insert(today)
    let first = noon.addingTimeInterval(-86_400 * 3)
    context.insert(session(day: "2026-03-07", language: .en, endedAt: first))
    context.insert(session(day: "2026-03-09", chars: 400, seconds: 60, accuracy: 0.99, endedAt: noon.addingTimeInterval(-86_400)))
    context.insert(session(day: "2026-03-10", chars: 100, endedAt: noon))
    let stat = KeyStat(language: "ru", character: "а")
    stat.keyCode = 3
    stat.presses = 50
    stat.errors = 5
    stat.ewmaMs = 250
    context.insert(stat)
    try context.save()

    let data = try AnalyticsLoader(context: context).summary(
        language: .ru, courses: [:], today: "2026-03-10", goalSeconds: 600, firstWeekday: 2)
    #expect(data.totals.today == 100)
    #expect(data.totals.week == 800)
    #expect(data.totals.all == 800)
    #expect(data.firstSessionDate == first)
    #expect(data.courseStartDate == noon.addingTimeInterval(-86_400))
    #expect(data.records.bestCpm[.ru] == nil)                 // 400 знаков с ошибками и 100 знаков вне проверки — не рекорд скорости
    #expect(data.records.bestAccuracy[.ru]?.value == 0.99)
    #expect(data.records.longestStreak == 2)
    #expect(data.calendar.weeks[52][0].status == .full)
    #expect(data.keys.map(\.keyCode) == [3])
}

// MARK: - Карточка «Дни»

@Test func dayMetricRowsListFlameVisitsAndGoal() {
    let streak = StreakSummary(current: 7, fullInRow: 3, fullInCurrent: 3, freezes: 1, longest: 15, today: .full,
                               statuses: [:], visitCurrent: 4, visitLongest: 9, visitTotal: 40,
                               goalCurrent: 2, goalLongest: 5, goalTotal: 22)
    let rows = DayMetricRow.rows(streak)
    #expect(rows.map(\.icon) == ["flame.fill", "figure.walk", "target"])
    #expect(rows.map(\.title) == ["Огонь", "Заходил", "Цель выполнена"])
    #expect(rows.map(\.current) == [7, 4, 2])
    #expect(rows.map(\.longest) == [15, 9, 5])
    #expect(rows.map(\.total) == [nil, 40, 22])
    #expect(rows.map(\.help) == [HelpText.freezes, HelpText.visitDays, HelpText.goalDays])
}

@Test func dayMetricIconsAreExistingSymbols() {
    let streak = StreakSummary(current: 0, fullInRow: 0, fullInCurrent: 0, freezes: 0, longest: 0, today: .none,
                               statuses: [:])
    for name in DayMetricRow.rows(streak).map(\.icon) + ["figure.walk", "target"] {
        #expect(NSImage(systemSymbolName: name, accessibilityDescription: nil) != nil, "нет символа «\(name)»")
    }
}

@MainActor @Test func loaderSummaryCarriesDayMetrics() throws {
    let container = try makeContainer()
    let context = container.mainContext
    for (key, seconds) in [("2026-03-08", 700.0), ("2026-03-09", 100), ("2026-03-10", 700)] {
        let day = DayRecord(logicalDay: key)
        day.activeSeconds = seconds
        day.completedExercises = 1
        context.insert(day)
    }
    try context.save()
    let data = try AnalyticsLoader(context: context).summary(
        language: .ru, courses: [:], today: "2026-03-10", goalSeconds: 600, firstWeekday: 2)
    #expect(data.streak.visitTotal == 3)
    #expect(data.streak.goalTotal == 2)
}
