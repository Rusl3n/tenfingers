import Foundation
import TypingCore

/// Один день недельной ленты.
struct WeekDay: Identifiable, Equatable {
    let key: String
    /// Короткое название дня недели («Пн»).
    let label: String
    let status: DayStatus
    let isToday: Bool
    /// День недели, который ещё не наступил: без статуса.
    let isFuture: Bool
    var id: String { key }
}

/// Всё, что показывает главная, посчитанное из сохранённого прогресса. Чистое значение: удобно проверять и рисовать.
struct HomeData: Equatable {
    let language: Language
    let streak: StreakSummary
    let goalMinutes: Int
    let todaySeconds: Double
    /// Календарная неделя от первого дня недели: семь логических дней, сегодня среди них, дни после него — будущие.
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
                     firstSessionDate: Date? = nil, firstWeekday: Int,
                     weekdaySymbols: [String] = weekdaySymbols(locale: Formatting.interfaceLocale())) -> HomeData {
        let week = weekKeys(today: today, firstWeekday: firstWeekday).map { key in
            let isFuture = key > today
            return WeekDay(key: key, label: weekdayLabel(key, symbols: weekdaySymbols),
                           status: isFuture ? DayStatus.none : streak.statuses[key] ?? DayStatus.none,
                           isToday: key == today, isFuture: isFuture)
        }
        // Показатели недели — по-прежнему последние 7 дней, а не календарная неделя: в понедельник она почти пуста.
        let weekSet = Set(StreakCalculator.dayKeys(from: StreakCalculator.dayKey(today, offset: -6), to: today))
        let points = Analytics.daily(sessions, language: language).filter { weekSet.contains($0.day) && $0.typedSessions > 0 }
        // Скорость и точность — только по дням с обычными упражнениями и с весом их времени: ритм-игра их не даёт.
        let weight = points.reduce(0.0) { $0 + $1.typedSeconds }
        let cpm = weight > 0 ? points.reduce(0.0) { $0 + $1.cpm * $1.typedSeconds } / weight : nil
        let accuracy = weight > 0 ? points.reduce(0.0) { $0 + $1.accuracy * $1.typedSeconds } / weight : nil
        let secondsByDay = days.mapValues(\.activeSeconds)
        return HomeData(language: language, streak: streak, goalMinutes: goalMinutes,
                        todaySeconds: days[today]?.activeSeconds ?? 0, week: week,
                        weekCpm: cpm, weekAccuracy: accuracy,
                        totalSeconds: Analytics.totals(secondsByDay: secondsByDay, today: today).all,
                        firstSessionDate: firstSessionDate ?? sessions.map(\.endedAt).min(),
                        focus: focus, weakKeys: weakKeys, canStartWeakSpots: canStartWeakSpots)
    }

    /// Семь ключей календарной недели, в которой лежит `today`, от `firstWeekday` (1 — воскресенье, 2 — понедельник);
    /// пусто, если ключ не читается.
    static func weekKeys(today: String, firstWeekday: Int) -> [String] {
        guard let weekday = AnalyticsDates.weekday(today) else { return [] }
        let start = StreakCalculator.dayKey(today, offset: -((weekday - firstWeekday + 7) % 7))
        return StreakCalculator.dayKeys(from: start, to: StreakCalculator.dayKey(start, offset: 6))
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
    /// Все уроки этапа засчитаны, проверка ниже порога: «Пересдать проверку» вместо «Продолжить курс».
    let retakeCheck: Bool
    let lessonRun: LessonRun?

    /// По `Course.continueTarget` (решение 13): урок, «Пересдать проверку» или «Курс пройден».
    /// `nil` — вести некуда, а курс не пройден (в курсе без уроков).
    static func make(course: Course, language: Language, passed: Set<String>, checkStars: [String: Int]) -> ContinueInfo? {
        let percent = Int(course.completion(passed: passed) * 100)
        switch course.continueTarget(passed: passed, checkStars: checkStars) {
        case .lesson(let lesson):
            return ContinueInfo(lessonTitle: lesson.localizedTitle, stageTitle: course.stage(of: lesson.id)?.localizedTitle ?? "",
                                percent: percent, retakeCheck: false,
                                lessonRun: LessonRun(language: language, lessonId: lesson.id))
        case .retakeCheck(let check):
            return ContinueInfo(lessonTitle: check.localizedTitle, stageTitle: course.stage(of: check.id)?.localizedTitle ?? "",
                                percent: percent, retakeCheck: true,
                                lessonRun: LessonRun(language: language, lessonId: check.id))
        case nil:
            guard course.isCompleted(passed: passed, checkStars: checkStars) else { return nil }
            return ContinueInfo(lessonTitle: nil, stageTitle: "", percent: percent, retakeCheck: false, lessonRun: nil)
        }
    }
}
