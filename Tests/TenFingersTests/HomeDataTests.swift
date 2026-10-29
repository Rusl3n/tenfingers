import AppKit
import Foundation
import Testing
import TypingCore
@testable import TenFingers

private let symbols = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
private let today = "2026-03-10"   // вторник

private func sample(day: String, language: Language = .ru, chars: Int = 600, seconds: Double = 120,
                    accuracy: Double = 0.9, completed: Bool = true, hour: Double = 12) -> SessionSummary {
    SessionSummary(day: day, endedAt: Date(timeIntervalSince1970: 1_773_144_000 + hour * 3600), language: language,
                   mode: .practice, chars: chars, activeSeconds: seconds, accuracy: accuracy, completed: completed)
}

private func make(days: [String: DayActivity] = [:], sessions: [SessionSummary] = [], language: Language = .ru,
                  firstWeekday: Int = 2) -> HomeData {
    let streak = StreakCalculator.summarize(days: days, today: today, goalSeconds: 600)
    return HomeData.make(language: language, streak: streak, days: days, sessions: sessions, today: today,
                         goalMinutes: 10, firstWeekday: firstWeekday, weekdaySymbols: symbols)
}

/// Календарная неделя от первого дня недели: сегодня (вторник) — второй день, дальше — будущие.
@Test func weekIsCalendarWeekFromFirstWeekday() {
    let data = make()
    #expect(data.week.map(\.key) == ["2026-03-09", "2026-03-10", "2026-03-11", "2026-03-12", "2026-03-13", "2026-03-14", "2026-03-15"])
    #expect(data.week.map(\.label) == ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"])
    #expect(data.week.filter(\.isToday).map(\.key) == [today])
    #expect(data.week.map(\.isFuture) == [false, false, true, true, true, true, true])
    #expect(data.week.filter(\.isFuture).allSatisfy { $0.status == .none })
}

@Test func weekStartsOnSundayWhenAsked() {
    let data = make(firstWeekday: 1)
    #expect(data.week.map(\.key).first == "2026-03-08" && data.week.map(\.key).last == "2026-03-14")
    #expect(data.week.map(\.label) == ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"])
    #expect(data.week.map(\.isFuture) == [false, false, false, true, true, true, true])
}

@Test func weekKeysForSaturday() {
    // Суббота 2026-10-24: при понедельнике это шестой день, воскресенье ещё впереди; при воскресенье суббота — последний день недели.
    #expect(HomeData.weekKeys(today: "2026-10-24", firstWeekday: 2).first == "2026-10-19")
    #expect(HomeData.weekKeys(today: "2026-10-24", firstWeekday: 2).last == "2026-10-25")
    #expect(HomeData.weekKeys(today: "2026-10-24", firstWeekday: 1).first == "2026-10-18")
    #expect(HomeData.weekKeys(today: "2026-10-24", firstWeekday: 1).last == "2026-10-24")
    #expect(HomeData.weekKeys(today: "2026-10-24", firstWeekday: 1).count == 7)
    // Первый день недели — сегодня: остальные шесть — будущие.
    #expect(HomeData.weekKeys(today: "2026-10-26", firstWeekday: 2).first == "2026-10-26")
    // Воскресенье при понедельнике — последний день недели.
    #expect(HomeData.weekKeys(today: "2026-10-25", firstWeekday: 2).first == "2026-10-19")
    #expect(HomeData.weekKeys(today: "garbage", firstWeekday: 2).isEmpty)
}

@Test func weekOfSaturdayWithMondayFirstHasFutureSunday() {
    let streak = StreakCalculator.summarize(days: [:], today: "2026-10-24", goalSeconds: 600)
    let data = HomeData.make(language: .ru, streak: streak, days: [:], sessions: [], today: "2026-10-24",
                             goalMinutes: 10, firstWeekday: 2, weekdaySymbols: symbols)
    #expect(data.week.map(\.key).first == "2026-10-19" && data.week.map(\.key).last == "2026-10-25")
    #expect(data.week.map(\.isFuture) == [false, false, false, false, false, false, true])
    #expect(data.week[5].isToday)
}

@Test func weekCarriesStatusesAndDaysBeforeFirstActivityAreEmpty() {
    let days = [
        "2026-03-08": DayActivity(activeSeconds: 700, completedExercises: 2),
        "2026-03-09": DayActivity(activeSeconds: 100, completedExercises: 1),
    ]
    let data = make(days: days, firstWeekday: 1)
    #expect(data.week.map(\.status) == [.full, .half, DayStatus.none, .none, .none, .none, .none])
}

@Test func metricsUseOnlyActiveLanguageWithinSevenDays() {
    let sessions = [
        sample(day: "2026-03-10", chars: 600, seconds: 120, accuracy: 0.9),               // 300 зн/мин
        sample(day: "2026-03-08", chars: 300, seconds: 120, accuracy: 0.8),               // 150 зн/мин
        sample(day: "2026-03-01", chars: 6000, seconds: 120, accuracy: 0.1),              // старше недели
        sample(day: "2026-03-10", language: .en, chars: 6000, seconds: 120, accuracy: 0.1),
    ]
    let data = make(sessions: sessions)
    // Взвешено по времени: (300 × 120 + 150 × 120) / 240 = 225; точность (0.9 + 0.8) / 2.
    #expect(abs((data.weekCpm ?? 0) - 225) < 0.001)
    #expect(abs((data.weekAccuracy ?? 0) - 0.85) < 0.001)
}

@Test func metricsAreNilWithoutCompletedExercises() {
    let data = make(sessions: [sample(day: today, completed: false)])
    #expect(data.weekCpm == nil)
    #expect(data.weekAccuracy == nil)
}

@Test func totalsAndFirstSessionComeFromAllHistory() {
    let days = [
        "2026-02-01": DayActivity(activeSeconds: 600, completedExercises: 1),
        "2026-03-10": DayActivity(activeSeconds: 90, completedExercises: 1),
    ]
    let sessions = [sample(day: today, hour: 3), sample(day: "2026-02-01", hour: -500)]
    let data = make(days: days, sessions: sessions)
    #expect(data.totalSeconds == 690)
    #expect(data.todaySeconds == 90)
    #expect(data.firstSessionDate == Date(timeIntervalSince1970: 1_773_144_000 - 500 * 3600))
}

@Test func emptyHistoryGivesEmptyHome() {
    let data = make()
    #expect(data.streak.current == 0)
    #expect(data.totalSeconds == 0)
    #expect(data.firstSessionDate == nil)
    #expect(data.todaySeconds == 0)
}

/// Названия дней недели — на языке интерфейса, а не региона.
@Test func weekdayLabelsFollowGivenLocale() {
    let ru = HomeData.weekdaySymbols(locale: Locale(identifier: "ru"))
    let streak = StreakCalculator.summarize(days: [:], today: today, goalSeconds: 600)
    let data = HomeData.make(language: .ru, streak: streak, days: [:], sessions: [], today: today, goalMinutes: 10,
                             firstWeekday: 2, weekdaySymbols: ru)
    #expect(data.week.map(\.label) == ["Пн", "Вт", "Ср", "Чт", "Пт", "Сб", "Вс"])
    #expect(HomeData.weekdaySymbols(locale: Locale(identifier: "en")).first == "Sun")
}

@Test func firstSessionDateCanComeFromSeparateQuery() {
    let first = Date(timeIntervalSince1970: 1_000_000)
    let streak = StreakCalculator.summarize(days: [:], today: today, goalSeconds: 600)
    let data = HomeData.make(language: .ru, streak: streak, days: [:], sessions: [sample(day: today)], today: today,
                             goalMinutes: 10, firstSessionDate: first, firstWeekday: 2, weekdaySymbols: symbols)
    #expect(data.firstSessionDate == first)
}

/// Подписи под числом серии: призыв заняться сегодня (если ещё не занимались); «из них полных» убрано.
@Test func streakHeaderLines() {
    func summary(current: Int, today: DayStatus) -> StreakSummary {
        StreakSummary(current: current, fullInRow: 0, fullInCurrent: 0, freezes: 0, longest: current,
                      today: today, statuses: [:])
    }
    #expect(StreakHeader.lines(summary(current: 0, today: .none))
        == ["Займитесь сегодня, чтобы начать серию"])
    #expect(StreakHeader.lines(summary(current: 3, today: .none))
        == ["Займитесь сегодня, чтобы не прервать серию"])
    #expect(StreakHeader.lines(summary(current: 4, today: .half)) == [])
}

/// Строки «Заходил» и «Цель» под числом серии: только когда есть хоть один день занятий.
@Test func streakHeaderDayMetrics() {
    let empty = StreakSummary(current: 0, fullInRow: 0, fullInCurrent: 0, freezes: 0, longest: 0,
                              today: .none, statuses: [:])
    #expect(StreakHeader.dayMetrics(empty).isEmpty)
    let streak = StreakSummary(current: 12, fullInRow: 0, fullInCurrent: 0, freezes: 0, longest: 12,
                               today: .full, statuses: [:], visitCurrent: 12, visitLongest: 20, visitTotal: 40,
                               goalCurrent: 5, goalLongest: 9, goalTotal: 22)
    let lines = StreakHeader.dayMetrics(streak)
    #expect(lines.map(\.icon) == ["figure.walk", "target"])
    #expect(lines.map(\.text) == ["Заходил: 12 дней подряд · всего 40", "Цель: 5 дней подряд · всего 22"])
    #expect(lines.map(\.help) == [HelpText.visitDays, HelpText.goalDays])
}

/// Английский текст строк берётся из Localization/en.lproj (в тестах `Bundle.main` без переводов приложения).
@Test func dayMetricsTextFollowsTheBundleLanguage() throws {
    let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().appendingPathComponent("Localization/en.lproj")
    let en = try #require(Bundle(url: url))
    let locale = Locale(identifier: "en")
    #expect(DayMetricsText.visits(current: 1, total: 3, bundle: en, locale: locale) == "Visited: 1 day in a row · 3 total")
    #expect(DayMetricsText.goals(current: 2, total: 7, bundle: en, locale: locale) == "Goal: 2 days in a row · 7 total")
}

@Test func futureDayIconExists() {
    #expect(NSImage(systemSymbolName: WeekStrip.futureIcon, accessibilityDescription: nil) != nil)
}

// MARK: - «Продолжить курс»

/// «Продолжить» ведёт по `continueTarget`: следующий урок, «Пересдать проверку» при проверке ниже порога,
/// экстерн — в открытый этап, «Курс пройден».
@Test func continueInfoFollowsTheGate() throws {
    let course = try CourseFixtureApp.ruMini()
    let stageOne = Set(course.stages[0].lessons.map(\.id))
    let all = Set(course.lessons.map(\.id))

    // Начало: первый урок этапа 1.
    let start = try #require(ContinueInfo.make(course: course, language: .ru, passed: [], checkStars: [:]))
    #expect(start.lessonRun?.lessonId == "ru2.s1.01")
    #expect(!start.retakeCheck && start.percent == 0 && start.stageTitle == "Этап 1")

    // Этап пройден, а проверка набрала ★ при пороге ★★ — «Пересдать проверку» того же этапа.
    let retake = try #require(ContinueInfo.make(course: course, language: .ru, passed: stageOne,
                                                checkStars: ["ru2.s1.check": 1]))
    #expect(retake.retakeCheck)
    #expect(retake.lessonRun?.lessonId == "ru2.s1.check")
    #expect(retake.stageTitle == "Этап 1" && retake.lessonTitle == course.lessons[4].localizedTitle && retake.percent == 50)

    // Порог взят: этап 2.
    let next = try #require(ContinueInfo.make(course: course, language: .ru, passed: stageOne,
                                              checkStars: ["ru2.s1.check": 2]))
    #expect(!next.retakeCheck && next.stageTitle == "Этап 2")
    #expect(next.lessonRun?.lessonId == "ru2.s2.01")

    // Экстерн: засчитана только проверка этапа 1 — главная ведёт в этап 2, а не в начало курса.
    let extern = try #require(ContinueInfo.make(course: course, language: .ru, passed: ["ru2.s1.check"],
                                                checkStars: ["ru2.s1.check": 2]))
    #expect(extern.stageTitle == "Этап 2" && extern.lessonRun?.lessonId == "ru2.s2.01" && !extern.retakeCheck)

    // Курс пройден: все уроки засчитаны и итоговая проверка набрала порог.
    let done = try #require(ContinueInfo.make(course: course, language: .ru, passed: all,
                                              checkStars: ["ru2.s1.check": 2, "ru2.s2.check": 3]))
    #expect(done.lessonTitle == nil && done.lessonRun == nil && !done.retakeCheck && done.percent == 100)

    // Итоговая проверка ниже порога — пересдать её.
    let last = try #require(ContinueInfo.make(course: course, language: .ru, passed: all,
                                              checkStars: ["ru2.s1.check": 2, "ru2.s2.check": 2]))
    #expect(last.retakeCheck && last.lessonRun?.lessonId == "ru2.s2.check")
}

/// Издание 1: следующий урок, без порога.
@Test func continueInfoInEditionOneIsTheNextLesson() throws {
    let course = try #require(try CourseCatalog.legacy(.ru))
    let first = course.lessons[0], second = course.lessons[1]
    let info = try #require(ContinueInfo.make(course: course, language: .ru, passed: [first.id], checkStars: [:]))
    #expect(info.lessonRun?.lessonId == second.id && !info.retakeCheck)
    let done = try #require(ContinueInfo.make(course: course, language: .ru, passed: Set(course.lessons.map(\.id)),
                                              checkStars: [:]))
    #expect(done.lessonTitle == nil && done.percent == 100)
}
