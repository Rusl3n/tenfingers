import Foundation

/// Период испытаний (6e, §10.2): ISO-неделя логических дней (понедельник–воскресенье) или календарный месяц.
public enum ChallengePeriod: Hashable, Sendable {
    /// Ключ — ISO-неделя `2026-W44` (год ISO-недели).
    case week(String)
    /// Ключ — месяц `2026-11`.
    case month(String)

    /// Ключ периода: `2026-W44` или `2026-11`; по нему выбираются испытания и хранятся получения ачивок.
    public var key: String {
        switch self {
        case .week(let key), .month(let key): key
        }
    }

    /// Первый логический день периода (`yyyy-MM-dd`).
    public var firstDay: String {
        switch self {
        case .week(let key): ChallengeCalendar.mondayOfWeek(key) ?? key
        case .month(let key): key + "-01"
        }
    }

    /// Последний логический день периода (воскресенье или последний день месяца).
    public var lastDay: String {
        switch self {
        case .week: StreakCalculator.dayKey(firstDay, offset: 6)
        case .month(let key): ChallengeCalendar.lastDayOfMonth(key) ?? key + "-28"
        }
    }

    /// Неделя, в которую входит логический день `day` (`yyyy-MM-dd`).
    public static func week(containing day: String) -> ChallengePeriod {
        .week(ChallengeCalendar.weekKey(day) ?? day)
    }

    /// Месяц, в который входит логический день `day` (`yyyy-MM-dd`).
    public static func month(containing day: String) -> ChallengePeriod {
        .month(String(day.prefix(7)))
    }

    var isMonth: Bool {
        if case .month = self { true } else { false }
    }
}

/// Календарные вычисления по ключам дней (ISO-недели и месяцы), всё в UTC: ключи уже логические даты.
enum ChallengeCalendar {
    private static let calendar: Calendar = {
        var calendar = Calendar(identifier: .iso8601)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    private static func date(_ day: String) -> Date? {
        let parts = day.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
    }

    static func weekKey(_ day: String) -> String? {
        guard let date = date(day) else { return nil }
        let parts = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
        guard let year = parts.yearForWeekOfYear, let week = parts.weekOfYear else { return nil }
        return String(format: "%04d-W%02d", year, week)
    }

    static func mondayOfWeek(_ key: String) -> String? {
        let parts = key.components(separatedBy: "-W")
        guard parts.count == 2, let year = Int(parts[0]), let week = Int(parts[1]),
              let monday = calendar.date(from: DateComponents(weekday: 2, weekOfYear: week, yearForWeekOfYear: year))
        else { return nil }
        let c = calendar.dateComponents([.year, .month, .day], from: monday)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    static func lastDayOfMonth(_ key: String) -> String? {
        guard let first = date(key + "-01"), let length = calendar.range(of: .day, in: .month, for: first)?.count
        else { return nil }
        return key + String(format: "-%02d", length)
    }
}

/// Испытание недели или месяца (6e, §10.2); `rawValue` — id из спецификации.
public enum ChallengeId: String, CaseIterable, Sendable {
    // Неделя.
    case weekGoal5 = "w.goal5"
    case weekVisit7 = "w.visit7"
    case weekChars = "w.chars"
    case weekClean = "w.clean"
    case weekStars = "w.stars"
    case weekTimes = "w.times"
    case weekVisits = "w.visits"
    case weekSpeed = "w.speed"
    case weekReview = "w.review"
    case weekPlan = "w.plan"
    // Лёгкий набор первой недели.
    case firstDays = "w.first.days"
    case firstLessons = "w.first.lessons"
    case firstGoal = "w.first.goal"
    // Месяц.
    case monthGoal20 = "m.goal20"
    case monthVisit28 = "m.visit28"
    case monthChars = "m.chars"
    case monthStage = "m.stage"
    case monthGrowth = "m.growth"

    /// «Трудное» (★): в наборе недели не больше одного.
    public var isHard: Bool { self == .weekSpeed }

    /// Испытание месяца.
    public var isMonthly: Bool {
        switch self {
        case .monthGoal20, .monthVisit28, .monthChars, .monthStage, .monthGrowth: true
        default: false
        }
    }
}

/// Параметры периода, зафиксированные по данным до его начала (§10.2): G — дневная цель (мин), C — скорость (зн/мин).
public struct ChallengeParameters: Equatable, Sendable {
    public let goalMinutes: Int
    public let cpm: Double

    public init(goalMinutes: Int, cpm: Double) {
        self.goalMinutes = goalMinutes
        self.cpm = cpm
    }
}

/// Прогресс одного испытания в его единицах (дни, знаки, упражнения, уроки; `w.times` — окна из 3, `w.speed` — 0/1,
/// `m.growth` — процент средней скорости к прошлому месяцу при цели 105). `progress` не больше `target` и равен ему
/// ровно тогда, когда испытание выполнено (`completedAt != nil`).
public struct ChallengeResult: Equatable, Sendable {
    public let id: ChallengeId
    public let progress: Int
    public let target: Int
    /// Завершённое упражнение, на котором набран порог (не позже `facts.now`); `nil` — не выполнено.
    public let completedAt: Date?

    public init(id: ChallengeId, progress: Int, target: Int, completedAt: Date?) {
        self.id = id
        self.progress = progress
        self.target = target
        self.completedAt = completedAt
    }
}

/// Испытания одного периода: у недели три, у месяца одно.
public struct ChallengePeriodResult: Equatable, Sendable {
    public let period: ChallengePeriod
    public let parameters: ChallengeParameters
    public let results: [ChallengeResult]
    /// У недели — когда выполнено третье испытание (все три); у месяца — когда выполнено его испытание.
    public let allDoneAt: Date?

    public init(period: ChallengePeriod, parameters: ChallengeParameters, results: [ChallengeResult],
                allDoneAt: Date?) {
        self.period = period
        self.parameters = parameters
        self.results = results
        self.allDoneAt = allDoneAt
    }
}

/// Испытания недели и месяца (6e, §10.2, решения 5–9 и 13 плана): выбор детерминирован ключом периода, прогресс
/// выводится из истории (`AchievementFacts`) — ничего не хранится.
public enum Challenges {
    /// Скорость C, если за 14 дней до периода нет упражнений.
    public static let defaultCpm = 100.0
    /// Цель G, мин, если неизвестна ни запись дня, ни текущая цель (в приложении цель всегда есть).
    public static let defaultGoalMinutes = 10
    /// Лёгкий набор первой недели пользователя (решение 6).
    public static let lightSet: [ChallengeId] = [.firstDays, .firstLessons, .firstGoal]

    private static let weeklyPool: [ChallengeId] = [.weekGoal5, .weekVisit7, .weekChars, .weekClean, .weekStars,
                                                    .weekTimes, .weekVisits, .weekSpeed, .weekReview, .weekPlan]

    /// Три испытания недели `key`: кандидаты по возрастанию `fnv1a("<ключ>#<id>")`, второе «трудное» пропускается.
    public static func weeklySet(key: String) -> [ChallengeId] {
        var chosen: [ChallengeId] = []
        for id in ranked(weeklyPool, key: key) where chosen.count < 3 {
            if id.isHard && chosen.contains(where: \.isHard) { continue }
            chosen.append(id)
        }
        return chosen
    }

    /// Испытание месяца `key` среди доступных: наименьший `fnv1a("<ключ>#<id>")`; `nil` — доступных нет.
    public static func monthlyChoice(key: String, available: [ChallengeId]) -> ChallengeId? {
        ranked(available, key: key).first
    }

    private static func ranked(_ ids: [ChallengeId], key: String) -> [ChallengeId] {
        ids.sorted { lhs, rhs in
            let (a, b) = (StableHash.fnv1a("\(key)#\(lhs.rawValue)"), StableHash.fnv1a("\(key)#\(rhs.rawValue)"))
            if a != b { return a < b }
            return ChallengeId.allCases.firstIndex(of: lhs)! < ChallengeId.allCases.firstIndex(of: rhs)!
        }
    }

    /// Испытания всех недель и месяцев от первого дня с занятиями до `facts.today` (без него — до календарного дня
    /// `facts.now`), по возрастанию первого дня периода, при равных — неделя раньше месяца. Периоды без занятий тоже
    /// есть (прогресс 0). Без занятий — пусто. Один проход по фактам на период, индексы по дням — один на проверку.
    public static func evaluate(_ facts: AchievementFacts) -> [ChallengePeriodResult] {
        Evaluator(facts).challengeResults()
    }

    // Швы для тестов: одно испытание/параметры/доступность без выбора набора.

    static func result(_ id: ChallengeId, in period: ChallengePeriod, facts: AchievementFacts) -> ChallengeResult {
        let engine = ChallengeEngine(Evaluator(facts))
        return engine.result(id, in: period, parameters: engine.parameters(for: period))
    }

    static func parameters(for period: ChallengePeriod, facts: AchievementFacts) -> ChallengeParameters {
        ChallengeEngine(Evaluator(facts)).parameters(for: period)
    }

    static func availableMonthly(for period: ChallengePeriod, facts: AchievementFacts) -> [ChallengeId] {
        ChallengeEngine(Evaluator(facts)).availableMonthly(for: period)
    }
}

extension Evaluator {
    /// Получения `challenge.week` (все три испытания недели) или `challenge.month`: ключ — период, дата — выполнение.
    func challengeOccurrences(week: Bool) -> [RawOccurrence] {
        challengeResults().compactMap { result in
            guard result.period.isMonth != week, let date = result.allDoneAt else { return nil }
            return (result.period.key, date, nil)
        }
    }
}
