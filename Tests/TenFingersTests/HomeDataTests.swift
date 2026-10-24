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

private func make(days: [String: DayActivity] = [:], sessions: [SessionSummary] = [], language: Language = .ru) -> HomeData {
    let streak = StreakCalculator.summarize(days: days, today: today, goalSeconds: 600)
    return HomeData.make(language: language, streak: streak, days: days, sessions: sessions, today: today,
                         goalMinutes: 10, weekdaySymbols: symbols)
}

@Test func weekIsSevenLogicalDaysEndingToday() {
    let data = make()
    #expect(data.week.map(\.key) == ["2026-03-04", "2026-03-05", "2026-03-06", "2026-03-07", "2026-03-08", "2026-03-09", "2026-03-10"])
    #expect(data.week.map(\.label) == ["Wed", "Thu", "Fri", "Sat", "Sun", "Mon", "Tue"])
    #expect(data.week.filter(\.isToday).map(\.key) == [today])
}

@Test func weekCarriesStatusesAndDaysBeforeFirstActivityAreEmpty() {
    let days = [
        "2026-03-08": DayActivity(activeSeconds: 700, completedExercises: 2),
        "2026-03-09": DayActivity(activeSeconds: 100, completedExercises: 1),
    ]
    let data = make(days: days)
    #expect(data.week.map(\.status) == [.none, .none, .none, .none, .full, .half, DayStatus.none])
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
                             weekdaySymbols: ru)
    #expect(data.week.map(\.label) == ["Ср", "Чт", "Пт", "Сб", "Вс", "Пн", "Вт"])
    #expect(HomeData.weekdaySymbols(locale: Locale(identifier: "en")).first == "Sun")
}

@Test func firstSessionDateCanComeFromSeparateQuery() {
    let first = Date(timeIntervalSince1970: 1_000_000)
    let streak = StreakCalculator.summarize(days: [:], today: today, goalSeconds: 600)
    let data = HomeData.make(language: .ru, streak: streak, days: [:], sessions: [sample(day: today)], today: today,
                             goalMinutes: 10, firstSessionDate: first, weekdaySymbols: symbols)
    #expect(data.firstSessionDate == first)
}

/// «из них полных» видно при любой серии, в том числе вместе с напоминанием заняться сегодня.
@Test func streakHeaderLines() {
    func summary(current: Int, full: Int, today: DayStatus) -> StreakSummary {
        StreakSummary(current: current, fullInRow: 0, fullInCurrent: full, freezes: 0, longest: current,
                      today: today, statuses: [:])
    }
    #expect(StreakHeader.lines(summary(current: 0, full: 0, today: .none))
        == ["Займитесь сегодня, чтобы начать серию"])
    #expect(StreakHeader.lines(summary(current: 3, full: 2, today: .none))
        == ["Займитесь сегодня, чтобы не прервать серию", "из них полных: 2"])
    #expect(StreakHeader.lines(summary(current: 4, full: 0, today: .half)) == ["из них полных: 0"])
}
