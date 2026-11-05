import Foundation
import SwiftData
import TypingCore

/// За какой период карточка «Мой прогресс» показывает календарь и цифры. «Без календаря» — календаря нет,
/// а цифры считаются за всё время.
enum ProgressPeriod: String, CaseIterable, Identifiable {
    case month, year, all
    var id: String { rawValue }

    var title: String {
        switch self {
        case .month: String(localized: "Этот месяц")
        case .year: String(localized: "Год")
        case .all: String(localized: "Без календаря")
        }
    }

    var showsCalendar: Bool { self != .all }
}

/// Что показывать на карточке «Мой прогресс»: семь переключателей листа «Поделиться», по умолчанию включены все.
struct ProgressCardContent: Equatable {
    /// Огонь серии: иконка и «N дней подряд».
    var showsStreak = true
    /// Строка про полные дни.
    var showsFullDays = true
    var showsTime = true
    var showsSpeed = true
    var showsAccuracy = true
    /// Строка «Искра: … подряд · всего …» (ключ настройки прежний — `shareProgressShowVisits`).
    var showsVisits = true
    /// Строка «Цель: … подряд · всего …».
    var showsGoalDays = true

    /// Хоть один из трёх показателей.
    var showsMetrics: Bool { showsTime || showsSpeed || showsAccuracy }

    /// Выключено всё.
    var isEmpty: Bool { !showsStreak && !showsFullDays && !showsVisits && !showsGoalDays && !showsMetrics }

    static func load(from defaults: UserDefaults) -> ProgressCardContent {
        func flag(_ key: String) -> Bool { defaults.object(forKey: key) as? Bool ?? true }
        return ProgressCardContent(
            showsStreak: flag(SettingsKey.shareProgressShowStreak),
            showsFullDays: flag(SettingsKey.shareProgressShowFullDays),
            showsTime: flag(SettingsKey.shareProgressShowTime),
            showsSpeed: flag(SettingsKey.shareProgressShowSpeed),
            showsAccuracy: flag(SettingsKey.shareProgressShowAccuracy),
            showsVisits: flag(SettingsKey.shareProgressShowVisits),
            showsGoalDays: flag(SettingsKey.shareProgressShowGoalDays))
    }

    func save(to defaults: UserDefaults) {
        defaults.set(showsStreak, forKey: SettingsKey.shareProgressShowStreak)
        defaults.set(showsFullDays, forKey: SettingsKey.shareProgressShowFullDays)
        defaults.set(showsTime, forKey: SettingsKey.shareProgressShowTime)
        defaults.set(showsSpeed, forKey: SettingsKey.shareProgressShowSpeed)
        defaults.set(showsAccuracy, forKey: SettingsKey.shareProgressShowAccuracy)
        defaults.set(showsVisits, forKey: SettingsKey.shareProgressShowVisits)
        defaults.set(showsGoalDays, forKey: SettingsKey.shareProgressShowGoalDays)
    }
}

/// Итоги периода: время, лучшая скорость и точность.
struct ProgressPeriodStats: Equatable {
    /// Чистое время занятий.
    let seconds: Double
    /// Лучшая скорость по правилу рекорда скорости (`Analytics.records`: проверка урока или текст от 300 знаков, без ошибок), максимум по языкам; `nil` — подходящего упражнения нет.
    let bestSpeed: Record?
    /// Взвешенная по знакам точность завершённых упражнений; `nil` — завершённых нет.
    let accuracy: Double?
}

/// Календарь месяца: недели по семь клеток, `nil` — день вне месяца.
struct MonthGrid: Equatable {
    struct Cell: Equatable {
        let key: String
        let day: Int
        let status: DayStatus
        /// День после сегодняшнего: не рисуется.
        let isFuture: Bool
    }

    /// Недели × 7; колонки начинаются с `firstWeekday`.
    let weeks: [[Cell?]]
    /// С какого дня недели начинается колонка (1 — воскресенье, 2 — понедельник).
    let firstWeekday: Int
    let year: Int
    let month: Int

    /// Месяц дня `today` («yyyy-MM-dd»); `statuses` — статусы дней серии.
    static func make(today: String, statuses: [String: DayStatus], firstWeekday: Int) -> MonthGrid {
        guard let parts = AnalyticsDates.components(today) else {
            return MonthGrid(weeks: [], firstWeekday: firstWeekday, year: 0, month: 0)
        }
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        let first = utc.date(from: DateComponents(year: parts.year, month: parts.month, day: 1))!
        let dayCount = utc.range(of: .day, in: .month, for: first)?.count ?? 30
        let prefix = String(format: "%04d-%02d-", parts.year, parts.month)
        let offset = ((utc.component(.weekday, from: first) - firstWeekday) % 7 + 7) % 7
        let slots: [Cell?] = Array(repeating: nil, count: offset) + (1...dayCount).map { day in
            let key = prefix + String(format: "%02d", day)
            return Cell(key: key, day: day, status: statuses[key] ?? DayStatus.none, isFuture: key > today)
        }
        let weeks = stride(from: 0, to: slots.count, by: 7).map { start -> [Cell?] in
            let week = Array(slots[start..<min(start + 7, slots.count)])
            return week + Array(repeating: nil, count: 7 - week.count)
        }
        return MonthGrid(weeks: weeks, firstWeekday: firstWeekday, year: parts.year, month: parts.month)
    }
}

/// Всё, что рисует карточка «Мой прогресс» (решение 19 спецификации фазы 5).
struct ProgressCardData: Equatable {
    /// Логический день, на который собраны данные («yyyy-MM-dd»).
    let today: String
    /// Серия: дней подряд и полных дней в ней.
    let streak: Int
    let fullDays: Int
    /// «Искра» и «Цель»: дней подряд и всего (`StreakSummary`).
    let visitCurrent: Int
    let visitTotal: Int
    let goalCurrent: Int
    let goalTotal: Int
    let monthGrid: MonthGrid
    let yearGrid: ActivityCalendar
    let month: ProgressPeriodStats
    let year: ProgressPeriodStats
    /// За всё время («Без календаря»).
    let allTime: ProgressPeriodStats
    /// Уровень из `Experience` (те же данные, что на «Главной»); `nil` — прочитать не удалось: строки уровня нет.
    var level: Int? = nil

    /// Месяц — с 1-го числа по сегодня, год — от первой клетки сетки 53×7 по сегодня, всё время — вся история.
    static func make(days: [String: DayActivity], sessions: [SessionSummary], today: String, goalSeconds: Double,
                     firstWeekday: Int, level: Int? = nil) -> ProgressCardData {
        let summary = StreakCalculator.summarize(days: days, today: today, goalSeconds: goalSeconds)
        let yearGrid = ActivityCalendar.make(today: today, statuses: summary.statuses, firstWeekday: firstWeekday)
        let monthStart = String(today.prefix(8)) + "01"
        let yearStart = yearGrid.weeks.first?.first?.key ?? monthStart
        func stats(from start: String) -> ProgressPeriodStats {
            let seconds = days.filter { $0.key >= start && $0.key <= today }.values.reduce(0) { $0 + $1.activeSeconds }
            let inPeriod = sessions.filter { $0.day >= start && $0.day <= today }
            let best = Analytics.records(inPeriod, longestStreak: 0).bestCpm.values.max { $0.value < $1.value }
            let completed = inPeriod.filter(\.completed)
            let chars = completed.reduce(0) { $0 + $1.chars }
            let accuracy = chars > 0
                ? completed.reduce(0) { $0 + $1.accuracy * Double($1.chars) } / Double(chars) : nil
            return ProgressPeriodStats(seconds: seconds, bestSpeed: best, accuracy: accuracy)
        }
        return ProgressCardData(
            today: today, streak: summary.current, fullDays: summary.fullInCurrent,
            visitCurrent: summary.visitCurrent, visitTotal: summary.visitTotal,
            goalCurrent: summary.goalCurrent, goalTotal: summary.goalTotal,
            monthGrid: MonthGrid.make(today: today, statuses: summary.statuses, firstWeekday: firstWeekday),
            yearGrid: yearGrid, month: stats(from: monthStart), year: stats(from: yearStart),
            allTime: stats(from: ""), level: level)
    }

    func stats(_ period: ProgressPeriod) -> ProgressPeriodStats {
        switch period {
        case .month: month
        case .year: year
        case .all: allTime
        }
    }
}

/// Читает из базы то, что нужно карточке: дни и сессии целиком — «Без календаря» считает показатели за всё время.
@MainActor
enum ProgressCardLoader {
    /// `firstWeekday` — явное значение (1 — воскресенье, 2 — понедельник); без него — настройка из `defaults`.
    /// `service` — источник уровня (приложение передаёт `.live`, тесты — свой, без стандартного домена).
    static func load(context: ModelContext, now: Date = .now, goalSeconds: Double, dayStartHour: Int,
                     firstWeekday: Int? = nil, defaults: UserDefaults = .standard,
                     service: AchievementService) throws -> ProgressCardData {
        let firstWeekday = firstWeekday ?? StoredSettings.firstWeekday(defaults)
        let snapshot = ProgressSnapshot(context: context)
        let today = LogicalDay.key(for: now, dayStartHour: dayStartHour)
        let days = try snapshot.dayActivities()
        let sessions = try snapshot.sessionSummaries()
        // Уровень — тот же снимок года, что у «Главной»; его ошибка не прячет карточку.
        let level = try? YearLoader(context: context, service: service).state().level
        return ProgressCardData.make(days: days, sessions: sessions, today: today, goalSeconds: goalSeconds,
                                     firstWeekday: firstWeekday, level: level)
    }
}

/// Тексты «Мой прогресс» на языке карточки: подпись периода, дни недели, месяцы и включённые показатели.
struct ProgressCardText: Equatable {
    struct Metric: Equatable {
        let title: String
        let value: String
    }

    /// «Октябрь 2026», «За год» или «За всё время».
    let periodLabel: String
    /// Что включено в листе: от этого зависит и состав карточки, и её раскладка.
    let content: ProgressCardContent
    let period: ProgressPeriod
    /// Подписи колонок месяца, начиная с первого дня недели.
    let weekdays: [String]
    /// Короткие названия месяцев 1…12 (подписи над сеткой года).
    let monthSymbols: [String]
    /// Только включённые показатели, в порядке «время, скорость, точность».
    let metrics: [Metric]

    var showsCalendar: Bool { period.showsCalendar }
    var showsStreak: Bool { content.showsStreak }

    /// Есть строки под огнём: полные дни, «Искра» или «Цель».
    var hasSubtitle: Bool { content.showsFullDays || content.showsVisits || content.showsGoalDays }

    /// Остался один огонь: ни строк под ним, ни показателей (и, значит, при «Без календаря» — крупная карточка с одним числом).
    var isFlameOnly: Bool { content.showsStreak && !hasSubtitle && metrics.isEmpty }

    /// Есть что показать слева от календаря (или вместо него): огонь, строки под ним или показатели.
    var hasSummary: Bool { content.showsStreak || hasSubtitle || !metrics.isEmpty }

    /// Строки под огнём в порядке «Полные дни», «Искра», «Цель» — только включённые.
    static func subtitleLines(data: ProgressCardData, content: ProgressCardContent, bundle: Bundle,
                              locale: Locale) -> [String] {
        var lines: [String] = []
        if content.showsFullDays {
            lines.append(String(localized: "Полных дней: \(data.fullDays)", bundle: bundle, locale: locale))
        }
        if content.showsVisits {
            lines.append(DayMetricsText.spark(current: data.visitCurrent, total: data.visitTotal, bundle: bundle,
                                              locale: locale))
        }
        if content.showsGoalDays {
            lines.append(DayMetricsText.goals(current: data.goalCurrent, total: data.goalTotal, bundle: bundle,
                                              locale: locale))
        }
        return lines
    }

    init(data: ProgressCardData, period: ProgressPeriod, content: ProgressCardContent, unit: SpeedUnit,
         bundle: Bundle, locale: Locale) {
        self.content = content
        self.period = period
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = locale
        let stats = data.stats(period)
        periodLabel = switch period {
        case .month: Self.monthTitle(year: data.monthGrid.year, month: data.monthGrid.month, calendar: calendar)
        case .year: String(localized: "За год", bundle: bundle, locale: locale)
        case .all: String(localized: "За всё время", bundle: bundle, locale: locale)
        }
        let symbols = calendar.shortStandaloneWeekdaySymbols
        weekdays = symbols.count == 7
            ? (0..<7).map { symbols[(data.monthGrid.firstWeekday - 1 + $0) % 7].capitalized(with: locale) } : []
        // Без точки («февр.» → «февр»): подпись над узкой колонкой должна быть короче.
        monthSymbols = calendar.shortStandaloneMonthSymbols.map { $0.trimmingCharacters(in: CharacterSet(charactersIn: ".")) }
        var metrics: [Metric] = []
        if content.showsTime {
            metrics.append(Metric(title: String(localized: "Время занятий", bundle: bundle, locale: locale),
                                  value: Formatting.duration(stats.seconds)))
        }
        if content.showsSpeed {
            metrics.append(Metric(title: String(localized: "Лучшая скорость", bundle: bundle, locale: locale),
                                  value: stats.bestSpeed.map { unit.format($0.value) }
                                      ?? String(localized: "пока нет", bundle: bundle, locale: locale)))
        }
        if content.showsAccuracy {
            metrics.append(Metric(title: String(localized: "Средняя точность", bundle: bundle, locale: locale),
                                  value: stats.accuracy.map { Formatting.percent($0, locale: locale) } ?? "—"))
        }
        self.metrics = metrics
    }

    /// «Октябрь 2026»: название месяца в именительном падеже, с заглавной.
    private static func monthTitle(year: Int, month: Int, calendar: Calendar) -> String {
        let names = calendar.standaloneMonthSymbols
        guard names.indices.contains(month - 1) else { return "" }
        let name = names[month - 1]
        return (name.prefix(1).uppercased() + name.dropFirst()) + " " + String(year)
    }
}

extension ShareCard {
    /// Карточка «Мой прогресс» из свежих данных базы (одна для главной и аналитики); ошибка чтения — исключение.
    @MainActor
    static func progress(context: ModelContext, goalSeconds: Double, dayStartHour: Int, now: Date = .now) throws
        -> ShareCard {
        let data = try ProgressCardLoader.load(context: context, now: now, goalSeconds: goalSeconds,
                                               dayStartHour: dayStartHour, service: .live(context: context))
        return ShareCard(.progress(data), now: now)
    }

    /// То же для кнопок «Поделиться»: при ошибке чтения — тост «Не удалось прочитать прогресс» и `nil`.
    @MainActor
    static func openProgress(context: ModelContext, goalSeconds: Double, dayStartHour: Int,
                             toasts: ToastCenter) -> ShareCard? {
        do {
            return try progress(context: context, goalSeconds: goalSeconds, dayStartHour: dayStartHour)
        } catch {
            toasts.show(Toast(icon: "exclamationmark.triangle", message: String(localized: "Не удалось прочитать прогресс"),
                              tint: .red))
            return nil
        }
    }
}
