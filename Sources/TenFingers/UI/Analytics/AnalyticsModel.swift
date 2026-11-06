import Foundation
import TypingCore

/// Период графиков скорости и точности.
enum AnalyticsPeriod: String, CaseIterable, Identifiable {
    case month, quarter, all

    var id: String { rawValue }

    var title: String {
        switch self {
        case .month: String(localized: "30 дней")
        case .quarter: String(localized: "90 дней")
        case .all: String(localized: "Всё время")
        }
    }

    private var days: Int? {
        switch self {
        case .month: 30
        case .quarter: 90
        case .all: nil
        }
    }

    /// Первый логический день периода (включая сегодня); `nil` — вся история.
    func startDay(today: String) -> String? {
        days.map { StreakCalculator.dayKey(today, offset: -($0 - 1)) }
    }
}

/// Ключи логических дней «yyyy-MM-dd» → даты для графиков и подписей.
enum AnalyticsDates {
    /// Год, месяц и день из ключа; `nil` для некорректного ключа.
    static func components(_ key: String) -> (year: Int, month: Int, day: Int)? {
        let parts = key.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return (parts[0], parts[1], parts[2])
    }

    /// Полдень этого дня в календаре `calendar`: точка графика не уезжает на соседний день из-за часового пояса.
    static func date(_ key: String, calendar: Calendar = .current) -> Date? {
        guard let parts = components(key) else { return nil }
        return calendar.date(from: DateComponents(year: parts.year, month: parts.month, day: parts.day, hour: 12))
    }

    /// День недели ключа: 1 — воскресенье … 7 — суббота (как `Calendar.component(.weekday)`).
    static func weekday(_ key: String) -> Int? {
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        guard let date = date(key, calendar: utc) else { return nil }
        return utc.component(.weekday, from: date)
    }
}

extension SpeedUnit {
    /// Значение скорости в этой единице (графики строятся в выбранной единице).
    func value(_ cpm: Double) -> Double {
        switch self {
        case .cpm: cpm
        case .wpm: cpm / 5
        }
    }

    /// Подпись оси скорости.
    var axisTitle: String {
        switch self {
        case .cpm: String(localized: "зн/мин")
        case .wpm: "WPM"
        }
    }
}

// MARK: - Графики

struct ChartPoint: Identifiable, Equatable {
    let day: String
    let date: Date
    /// Знаков в минуту.
    let cpm: Double
    /// 0…1.
    let accuracy: Double
    var id: String { day }
}

/// Пунктирная линия тренда скорости от первой до последней точки.
struct TrendLine: Equatable {
    let startDate: Date
    let endDate: Date
    let startCpm: Double
    let endCpm: Double
}

/// Точки графиков по дням с завершёнными упражнениями и тренд скорости (`Analytics.trend` по порядку точек).
struct ChartSeries: Equatable {
    let points: [ChartPoint]
    let trend: TrendLine?

    static let empty = ChartSeries(points: [], trend: nil)

    /// Для линии нужно хотя бы две точки.
    var hasEnoughData: Bool { points.count >= 2 }

    static func make(_ daily: [DailyPoint], calendar: Calendar = .current) -> ChartSeries {
        let points = daily.filter { $0.typedSessions > 0 }.compactMap { point in
            AnalyticsDates.date(point.day, calendar: calendar).map {
                ChartPoint(day: point.day, date: $0, cpm: point.cpm, accuracy: point.accuracy)
            }
        }
        guard let first = points.first, let last = points.last,
              let line = Analytics.trend(points.map(\.cpm)) else { return ChartSeries(points: points, trend: nil) }
        let trend = TrendLine(startDate: first.date, endDate: last.date, startCpm: line.intercept,
                              endCpm: line.intercept + line.slope * Double(points.count - 1))
        return ChartSeries(points: points, trend: trend)
    }
}

// MARK: - Тепловая карта и пальцы

/// Строка `KeyStat`: символ и его статистика.
struct KeyStatEntry: Equatable {
    let character: String
    let stat: KeyStatSummary
}

/// Статистика физической клавиши: строки заглавной и строчной буквы слиты по `keyCode`.
struct KeyInfo: Equatable, Identifiable {
    let keyCode: UInt16
    /// Символ клавиши в языке статистики (строчный).
    let label: String
    let stat: KeyStatSummary

    var id: UInt16 { keyCode }
    var errorRate: Double { stat.presses > 0 ? Double(stat.errors) / Double(stat.presses) : 0 }

    /// Подсказка при наведении: «ф — нажатий: 120, ошибок: 5,0%, 210 мс».
    func helpText(locale: Locale = .current) -> String {
        let percent = Formatting.percent(errorRate, locale: locale)
        let presses = stat.presses
        guard let ms = stat.ewmaMs else {
            return String(localized: "\(label) — нажатий: \(presses), ошибок: \(percent)", locale: locale)
        }
        let rounded = Int(ms.rounded())
        return String(localized: "\(label) — нажатий: \(presses), ошибок: \(percent), \(rounded) мс", locale: locale)
    }
}

enum HeatmapModel {
    /// Сливает строки одной клавиши: нажатия и ошибки складываются, время — среднее, взвешенное по нажатиям.
    static func merge(_ entries: [KeyStatEntry]) -> [KeyInfo] {
        Dictionary(grouping: entries, by: \.stat.keyCode).map { code, group in
            let presses = group.reduce(0) { $0 + $1.stat.presses }
            let errors = group.reduce(0) { $0 + $1.stat.errors }
            let timed = group.filter { $0.stat.ewmaMs != nil && $0.stat.presses > 0 }
            let timedPresses = timed.reduce(0) { $0 + $1.stat.presses }
            let ms = timedPresses > 0
                ? timed.reduce(0.0) { $0 + ($1.stat.ewmaMs ?? 0) * Double($1.stat.presses) } / Double(timedPresses)
                : group.compactMap(\.stat.ewmaMs).first
            let main = group.max { $0.stat.presses < $1.stat.presses }
            return KeyInfo(keyCode: code, label: (main?.character ?? "").lowercased(),
                           stat: KeyStatSummary(keyCode: code, presses: presses, errors: errors, ewmaMs: ms))
        }.sorted { $0.keyCode < $1.keyCode }
    }

    /// 0…1 по клавишам: 0 — лучшая, 1 — худшая (см. `Analytics.heat`).
    static func heat(_ keys: [KeyInfo], mode: HeatMode) -> [UInt16: Double] {
        Analytics.heat(keys.map(\.stat), mode: mode)
    }
}

/// Строка таблицы пальцев.
struct FingerRow: Identifiable, Equatable {
    let finger: Finger
    let presses: Int
    let errorRate: Double
    let averageMs: Double?
    /// Длина полосы ошибок относительно худшего пальца (0…1).
    let barFraction: Double

    var id: Finger { finger }

    /// Левая рука от мизинца к указательному, правая — от указательного к мизинцу, большие пальцы последними.
    static let order: [Finger] = [.leftPinky, .leftRing, .leftMiddle, .leftIndex,
                                  .rightIndex, .rightMiddle, .rightRing, .rightPinky, .thumb]

    var title: String {
        if finger == .thumb { return String(localized: "большие пальцы").localizedCapitalizedFirst }
        return finger.displayName.localizedCapitalizedFirst
    }

    static func rows(_ keys: [KeyInfo]) -> [FingerRow] {
        let stats = Dictionary(uniqueKeysWithValues: Analytics.fingers(keys.map(\.stat)).map { ($0.finger, $0) })
        let worst = stats.values.map(\.errorRate).max() ?? 0
        return order.map { finger in
            let stat = stats[finger]
            let rate = stat?.errorRate ?? 0
            return FingerRow(finger: finger, presses: stat?.presses ?? 0, errorRate: rate,
                             averageMs: stat?.averageMs, barFraction: worst > 0 ? rate / worst : 0)
        }
    }
}

extension String {
    /// Первая буква заглавная, остальное как есть: «левый мизинец» → «Левый мизинец».
    var localizedCapitalizedFirst: String {
        guard let first else { return self }
        return String(first).localizedUppercase + dropFirst()
    }
}

// MARK: - Календарь

/// Календарь активности в стиле GitHub: колонки — недели, строки — дни недели.
struct ActivityCalendar: Equatable {
    struct Cell: Identifiable, Equatable {
        let key: String
        let status: DayStatus
        /// День после сегодняшнего (в последней неделе): не рисуется.
        let isFuture: Bool
        var id: String { key }
    }

    /// Подпись месяца над колонкой, с которой он начинается (по первому дню колонки).
    struct MonthLabel: Equatable {
        let column: Int
        /// 1…12.
        let month: Int
    }

    static let weekCount = 53
    /// Подписи месяцев не ближе стольких колонок друг к другу.
    static let minimumLabelGap = 3

    let weeks: [[Cell]]
    let monthLabels: [MonthLabel]
    /// С какого дня недели начинается колонка (1 — воскресенье, 2 — понедельник).
    let firstWeekday: Int

    /// `firstWeekday` — первый день недели (1 — воскресенье, 2 — понедельник), как `Calendar.firstWeekday`.
    static func make(today: String, statuses: [String: DayStatus], weekCount: Int = weekCount,
                     firstWeekday: Int) -> ActivityCalendar {
        let weekday = AnalyticsDates.weekday(today) ?? firstWeekday
        let lastStart = StreakCalculator.dayKey(today, offset: -((weekday - firstWeekday + 7) % 7))
        let firstStart = StreakCalculator.dayKey(lastStart, offset: -7 * (weekCount - 1))
        let weeks = (0..<weekCount).map { column in
            let start = StreakCalculator.dayKey(firstStart, offset: 7 * column)
            return (0..<7).map { row in
                let key = StreakCalculator.dayKey(start, offset: row)
                return Cell(key: key, status: statuses[key] ?? DayStatus.none, isFuture: key > today)
            }
        }
        var labels: [MonthLabel] = []
        var previousMonth: Int?
        for (column, week) in weeks.enumerated() {
            guard let month = week.first.flatMap({ AnalyticsDates.components($0.key)?.month }) else { continue }
            if month != previousMonth {
                if let last = labels.last, column - last.column < minimumLabelGap { labels.removeLast() }
                labels.append(MonthLabel(column: column, month: month))
            }
            previousMonth = month
        }
        return ActivityCalendar(weeks: weeks, monthLabels: labels, firstWeekday: firstWeekday)
    }
}

// MARK: - История

struct HistoryRow: Identifiable, Equatable {
    let id: UUID
    let endedAt: Date
    let modeTitle: String
    let language: Language?
    /// Урок и шаг или источник текста; `nil`, если назвать нечего.
    let title: String?
    let cpm: Double
    let accuracy: Double
    let seconds: Double
    let abandoned: Bool
}

enum SessionHistory {
    /// Сколько последних записей показывает история.
    static let limit = 50
    /// Сколько строк видно до «Показать все».
    static let collapsedCount = 10

    /// Строки, видимые в свёрнутой или развёрнутой истории.
    static func visible<Row>(_ rows: [Row], expanded: Bool) -> [Row] {
        expanded ? rows : Array(rows.prefix(collapsedCount))
    }

    /// Есть ли что разворачивать.
    static func canExpand(count: Int) -> Bool { count > collapsedCount }

    static func modeTitle(_ mode: String) -> String {
        switch ExerciseMode(rawValue: mode) {
        case .course: String(localized: "Урок")
        case .adaptive: String(localized: "Тренировка")
        case .weak: String(localized: "Слабые места")
        case .practice: String(localized: "Практика")
        case .rhythm: String(localized: "Ритм")
        case .errorWords: String(localized: "Слова с ошибками")
        case .measure: String(localized: "Замер скорости")
        case nil: mode
        }
    }

    /// Название источника практики по `SessionRecord.source`; `nil` для тренировок и неизвестных значений.
    static func sourceTitle(_ source: String?, library: [LibraryText]) -> String? {
        switch source {
        case "words": return String(localized: "Частотные слова")
        case "symbols": return String(localized: "Цифры и символы")
        case "custom": return String(localized: "Свой текст")
        case "plan:text": return String(localized: "Текст плана")
        case "plan:review": return String(localized: "Повтор плана")
        case let source? where source.hasPrefix("library:"):
            let id = source.dropFirst("library:".count)
            return library.first { $0.id == id }?.title
        default: return nil
        }
    }

    /// Урок текущего курса — «<название>[ · <шаг>]»; иначе урок прежнего курса (`legacy`, сессии издания 1 сохраняют
    /// названия) — то же с пометкой «(курс 1.x)»; иначе `nil`.
    static func lessonTitle(lessonId: String?, kind: String?, course: Course?, legacy: Course? = nil) -> String? {
        guard let lessonId else { return nil }
        func title(_ lesson: Lesson) -> String {
            guard let step = kind.flatMap(ExerciseKind.init(rawValue:)) else { return lesson.localizedTitle }
            return "\(lesson.localizedTitle) · \(step.localizedTitle)"
        }
        if let lesson = course?.lessons.first(where: { $0.id == lessonId }) { return title(lesson) }
        if let lesson = legacy?.lessons.first(where: { $0.id == lessonId }) {
            let name = title(lesson)
            return String(localized: "\(name) (курс 1.x)")
        }
        return nil
    }
}

// MARK: - Прогресс курса

/// Урок из `LessonProgress`: пройден ли и сколько звёзд сохранено.
struct StoredLesson: Equatable {
    let lessonId: String
    let passed: Bool
    let storedStars: Int
}

struct CourseProgressRow: Identifiable, Equatable {
    let language: Language
    let passed: Int
    let total: Int
    let stars: Int
    /// Строка курса издания 1 (архив).
    let isArchive: Bool
    /// Средняя скорость проверок этапов, если курс издания 2 пройден и она не ниже 120 зн/мин (`Certificate`): у строки
    /// появляется кнопка «Сертификат». У архива — всегда `nil`.
    var certificateAverage: Double? = nil
    /// Состояние пути к «Сертификату» у курса издания 2, пока он не получен (фаза 8, §4); иначе `nil`.
    var certificateProgress: CertificateProgress? = nil

    var id: String { "\(language.rawValue)\(isArchive ? ".v1" : "")" }
    /// «Русский» или «Курс 1.x (архив) · Русский».
    var title: String {
        isArchive ? String(localized: "Курс 1.x (архив) · \(language.displayName)") : language.displayName
    }
    var maxStars: Int { total * LessonScoring.maxStars }
    var fraction: Double { total > 0 ? Double(passed) / Double(total) : 0 }

    /// Путь к «Сертификату»: только у курса издания 2 и пока сертификат не получен.
    static func certificateProgress(course: Course, passed: Set<String>, sessions: [SessionSummary]) -> CertificateProgress? {
        guard course.edition >= 2 else { return nil }
        let progress = Certificate.progress(course: course, passed: passed, sessions: sessions)
        return progress.earned ? nil : progress
    }

    /// Звёзды — по тому же правилу, что на карте курса: `LessonScoring.effectiveStars` с целью урока
    /// `Course.targetCpm(for:)` (история шагов урока, иначе база, у пройденного урока не меньше одной).
    /// `sessions` — завершённые шаги уроков курса.
    static func make(course: Course, lessons: [StoredLesson], sessions: [SessionSummary]) -> CourseProgressRow {
        let stored = Dictionary(lessons.map { ($0.lessonId, $0) }, uniquingKeysWith: { first, _ in first })
        let byLesson = Dictionary(grouping: sessions) { $0.lessonId ?? "" }
        var passed = 0, stars = 0
        var passedIds: Set<String> = []
        for stage in course.stages {
            for lesson in stage.lessons {
                let record = stored[lesson.id]
                let isPassed = record?.passed == true
                if isPassed {
                    passed += 1
                    passedIds.insert(lesson.id)
                }
                stars += LessonScoring.effectiveStars(sessions: byLesson[lesson.id] ?? [], lessonId: lesson.id,
                                                      targetCpm: course.targetCpm(for: lesson.id) ?? 0,
                                                      passed: isPassed,
                                                      storedStars: record?.storedStars ?? 0)
            }
        }
        return CourseProgressRow(
            language: course.language, passed: passed, total: course.lessons.count, stars: stars,
            isArchive: course.edition == 1,
            certificateAverage: Certificate.eligibleAverage(course: course, passed: passedIds, sessions: sessions),
            certificateProgress: certificateProgress(course: course, passed: passedIds, sessions: sessions))
    }
}
