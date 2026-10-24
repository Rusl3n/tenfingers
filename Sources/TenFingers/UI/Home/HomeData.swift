import Foundation
import TypingCore

/// Один день недельной ленты.
struct WeekDay: Identifiable, Equatable {
    let key: String
    /// Короткое название дня недели («Пн»).
    let label: String
    let status: DayStatus
    let isToday: Bool
    var id: String { key }
}

/// Всё, что показывает главная, посчитанное из сохранённого прогресса. Чистое значение: удобно проверять и рисовать.
struct HomeData: Equatable {
    let language: Language
    let streak: StreakSummary
    let goalMinutes: Int
    let todaySeconds: Double
    /// Последние 7 логических дней, по возрастанию; сегодня — последний.
    let week: [WeekDay]
    /// Средняя скорость активного курса за 7 дней (знаков в минуту) или `nil`, если упражнений не было.
    let weekCpm: Double?
    let weekAccuracy: Double?
    let totalSeconds: Double
    let firstSessionDate: Date?
    /// Буква в фокусе адаптивной тренировки и слабые клавиши (пусто, пока данных мало).
    let focus: Character?
    let weakKeys: [Character]
    let canStartWeakSpots: Bool

    static func make(language: Language, streak: StreakSummary, days: [String: DayActivity],
                     sessions: [SessionSummary], today: String, goalMinutes: Int,
                     focus: Character? = nil, weakKeys: [Character] = [], canStartWeakSpots: Bool = false,
                     firstSessionDate: Date? = nil,
                     weekdaySymbols: [String] = weekdaySymbols(locale: Formatting.interfaceLocale())) -> HomeData {
        let weekKeys = StreakCalculator.dayKeys(from: StreakCalculator.dayKey(today, offset: -6), to: today)
        let week = weekKeys.map { key in
            WeekDay(key: key, label: weekdayLabel(key, symbols: weekdaySymbols),
                    status: streak.statuses[key] ?? DayStatus.none, isToday: key == today)
        }
        let weekSet = Set(weekKeys)
        let points = Analytics.daily(sessions, language: language).filter { weekSet.contains($0.day) && $0.sessions > 0 }
        let weight = points.reduce(0.0) { $0 + $1.seconds }
        let cpm = weight > 0 ? points.reduce(0.0) { $0 + $1.cpm * $1.seconds } / weight : nil
        let accuracy = weight > 0 ? points.reduce(0.0) { $0 + $1.accuracy * $1.seconds } / weight : nil
        let secondsByDay = days.mapValues(\.activeSeconds)
        return HomeData(language: language, streak: streak, goalMinutes: goalMinutes,
                        todaySeconds: days[today]?.activeSeconds ?? 0, week: week,
                        weekCpm: cpm, weekAccuracy: accuracy,
                        totalSeconds: Analytics.totals(secondsByDay: secondsByDay, today: today).all,
                        firstSessionDate: firstSessionDate ?? sessions.map(\.endedAt).min(),
                        focus: focus, weakKeys: weakKeys, canStartWeakSpots: canStartWeakSpots)
    }

    /// Короткие названия дней недели (с воскресенья) на языке `locale`; для главной — язык интерфейса,
    /// как у `Formatting.days`, а не регион системы.
    static func weekdaySymbols(locale: Locale) -> [String] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = locale
        return calendar.shortWeekdaySymbols
    }

    /// Название дня недели по ключу «yyyy-MM-dd»; `symbols` — как `Calendar.shortWeekdaySymbols` (с воскресенья).
    static func weekdayLabel(_ key: String, symbols: [String]) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let parts = key.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3, symbols.count == 7,
              let date = calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
        else { return "" }
        return symbols[calendar.component(.weekday, from: date) - 1].localizedCapitalized
    }
}

/// Карточка «Продолжить курс»: уже готовые подписи (курс не нужен самой карточке).
struct ContinueInfo: Equatable {
    /// `nil`, если курс пройден.
    let lessonTitle: String?
    let stageTitle: String
    let percent: Int
    let lessonRun: LessonRun?
}
