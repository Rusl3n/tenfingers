import Foundation

/// Какие страницы включены в настройках виджета (три переключателя «Серия», «Цель дня», «Ачивки»).
/// Простые `Bool`, без списков: список разбирает системная служба, а ей ad-hoc подпись не подходит.
public struct WidgetPageSelection: Equatable, Sendable {
    public var streak: Bool
    public var goal: Bool
    public var achievements: Bool

    public init(streak: Bool = true, goal: Bool = true, achievements: Bool = true) {
        self.streak = streak
        self.goal = goal
        self.achievements = achievements
    }

    /// Ни одного включённого — как все три.
    public var isEmpty: Bool { !streak && !goal && !achievements }
}

/// Страница виджета: что нарисовать в одной записи ленты.
public enum WidgetPage: Equatable, Sendable {
    case streak
    case goal
    case achievements([WidgetSnapshot.Item])
    /// Нет снимка: «Откройте «Десять пальцев»».
    case placeholder

    /// Куда ведёт нажатие на виджет.
    public var link: URL {
        switch self {
        case .achievements: WidgetLink.achievements
        default: WidgetLink.home
        }
    }
}

/// «Сегодня» с поправкой на возраст снимка: если логический день файла не сегодняшний, день считается несделанным.
public struct WidgetToday: Equatable, Sendable {
    public var fire: WidgetSnapshot.FireToday
    public var sparkLit: Bool
    public var doneMinutes: Int
    /// Файлу больше 36 часов: показываем подпись «давно не открывали».
    public var isStale: Bool

    public init(fire: WidgetSnapshot.FireToday, sparkLit: Bool, doneMinutes: Int, isStale: Bool) {
        self.fire = fire
        self.sparkLit = sparkLit
        self.doneMinutes = doneMinutes
        self.isStale = isStale
    }
}

/// Чистая логика ленты виджета: какие страницы, в какие моменты, что скрыть. Только Foundation.
public enum WidgetTimeline {
    /// Допустимые значения «Менять каждые, мин».
    public static let intervalRange = 5...60
    /// Интервал по умолчанию, минуты.
    public static let defaultIntervalMinutes = 15
    /// На сколько вперёд строится лента.
    public static let horizon: TimeInterval = 2 * 3600
    /// Час начала логического дня по умолчанию: его берёт разбор файла без поля `dayStartHour` (как в приложении).
    public static let defaultDayStartHour = 4

    /// Интервал смены, зажатый в `intervalRange`.
    public static func clampedInterval(_ minutes: Int) -> Int {
        min(max(minutes, intervalRange.lowerBound), intervalRange.upperBound)
    }

    /// Ачивки с учётом «Скрывать шуточные 18+»: выключено — как в приложении (`appAdult`), включено — скрывать всегда.
    public static func visibleAchievements(_ items: [WidgetSnapshot.Item], hideAdult: Bool,
                                           appAdult: Bool) -> [WidgetSnapshot.Item] {
        let showAdult = !hideAdult && appAdult
        return showAdult ? items : items.filter { !$0.adult }
    }

    /// Страницы по настройке, в порядке Серия, Цель, Ачивки. Нет снимка — одна заглушка. Ни одной включённой — все три.
    /// Ачивки пропускаются, если после фильтра пусто; исключение — когда включены только они.
    public static func pages(selection: WidgetPageSelection, snapshot: WidgetSnapshot?,
                             hideAdult: Bool) -> [WidgetPage] {
        guard let snapshot else { return [.placeholder] }
        let selection = selection.isEmpty ? WidgetPageSelection() : selection
        let items = visibleAchievements(snapshot.achievements, hideAdult: hideAdult, appAdult: snapshot.adultHumor)
        var pages: [WidgetPage] = []
        if selection.streak { pages.append(.streak) }
        if selection.goal { pages.append(.goal) }
        if selection.achievements, !items.isEmpty || pages.isEmpty { pages.append(.achievements(items)) }
        return pages
    }

    /// Записи ленты: шаг — зажатый интервал, записи на два часа вперёд (первая — `start`), страницы по кругу
    /// начиная со страницы номер `offset` (счётчик нажатий). При одной странице сетка та же, чтобы «сегодня»
    /// и «давно не открывали» пересчитывались.
    public static func entries(pages: [WidgetPage], start: Date, intervalMinutes: Int = defaultIntervalMinutes,
                               offset: Int = 0) -> [(Date, WidgetPage)] {
        let pages = pages.isEmpty ? [WidgetPage.placeholder] : pages
        let minutes = clampedInterval(intervalMinutes)
        let step = Double(minutes) * 60
        let count = Int(horizon / step) + 1
        return (0..<count).map { index in
            (start.addingTimeInterval(Double(index) * step),
             pages[pageIndex(offset: offset, entry: index, pageCount: pages.count)])
        }
    }

    /// Номер страницы, которую показывает запись `entry` ленты, начатой со смещения `offset`.
    public static func pageIndex(offset: Int, entry: Int, pageCount: Int) -> Int {
        let count = max(pageCount, 1)
        return (((offset % count) + count) % count + entry) % count
    }

    /// Смещение ленты после нажатия «Менять по нажатию»: страница, следующая за показанной,
    /// даже если показанную выбрал таймер, а не прошлое нажатие.
    public static func nextOffset(afterShown index: Int, pageCount: Int) -> Int {
        (index + 1) % max(pageCount, 1)
    }

    /// Логический день `yyyy-MM-dd`: до `dayStartHour` ещё вчерашний. Те же правила, что у `LogicalDay` в приложении.
    public static func logicalDay(for date: Date, dayStartHour: Int = defaultDayStartHour,
                                  calendar: Calendar = .current) -> String {
        let startOfDay = calendar.startOfDay(for: date)
        let day = calendar.component(.hour, from: date) < dayStartHour
            ? calendar.date(byAdding: .day, value: -1, to: startOfDay) ?? startOfDay
            : startOfDay
        let parts = calendar.dateComponents([.year, .month, .day], from: day)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    /// Состояние «сегодня» на момент `now`. Серию не пересчитываем: берём то, что записано в файле.
    public static func today(for snapshot: WidgetSnapshot, now: Date, dayStartHour: Int = defaultDayStartHour,
                             calendar: Calendar = .current) -> WidgetToday {
        let isToday = snapshot.isToday(logicalDay(for: now, dayStartHour: dayStartHour, calendar: calendar))
        return WidgetToday(
            fire: isToday ? snapshot.fire.today : .none,
            sparkLit: isToday && snapshot.spark.today,
            doneMinutes: isToday ? snapshot.goal.doneMinutes : 0,
            isStale: snapshot.isStale(now: now))
    }
}

/// Падеж числа для подписей виджета («1 день», «2 дня», «5 дней», «1 day», «2 days»).
public enum WidgetPlural {
    public enum Category: Sendable { case one, few, many }

    public static func category(_ count: Int, language: String) -> Category {
        let n = abs(count)
        if language == "ru" {
            if n % 10 == 1, n % 100 != 11 { return .one }
            if (2...4).contains(n % 10), !(12...14).contains(n % 100) { return .few }
            return .many
        }
        return n == 1 ? .one : .many
    }
}
