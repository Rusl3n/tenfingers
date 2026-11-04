import Foundation

/// Откуда опыт (6e, §10.3, решение 10 плана).
public enum ExperienceSource: String, Sendable {
    case exercise, lessonPassed, lessonStar, stagePassed, coursePassed, fullDay, planDone
    /// Испытание недели (+100 за каждое), «все три испытания недели» (+100 ещё раз) и испытание месяца (+500).
    case challengeWeek, challengeWeekAll, challengeMonth
}

/// Одно начисление опыта: дата не позже `facts.now`, сумма больше нуля.
public struct ExperienceEvent: Equatable, Sendable {
    public let date: Date
    public let amount: Int
    public let source: ExperienceSource

    public init(date: Date, amount: Int, source: ExperienceSource) {
        self.date = date
        self.amount = amount
        self.source = source
    }
}

/// Переход на уровень `level` (с 2): дата — начисление, после которого порог уровня взят.
public struct LevelUp: Equatable, Sendable {
    public let level: Int
    public let date: Date

    public init(level: Int, date: Date) {
        self.level = level
        self.date = date
    }
}

/// Опыт за неделю: ключ — ISO-неделя логических дней (`2026-W45`, как у `ChallengePeriod`).
public struct WeeklyExperience: Equatable, Sendable {
    public let week: String
    public let amount: Int

    public init(week: String, amount: Int) {
        self.week = week
        self.amount = amount
    }
}

/// Журнал опыта: всё выводится из истории и ничего не хранится. Единственный источник уровней, ачивок уровней и
/// недельного графика.
public struct ExperienceLedger: Equatable, Sendable {
    /// Начисления по возрастанию даты; при равных датах — в порядке источников (`Experience.ledger`).
    public let events: [ExperienceEvent]
    public let total: Int
    /// Переходы на уровни 2, 3, … по возрастанию; один большой шаг даёт несколько переходов с одной датой.
    public let levelUps: [LevelUp]
    private let weeks: [WeeklyExperience]

    init(events: [ExperienceEvent], levelUps: [LevelUp], weeks: [WeeklyExperience]) {
        self.events = events
        total = events.reduce(0) { $0 + $1.amount }
        self.levelUps = levelUps
        self.weeks = weeks
    }

    /// Опыт, набранный не позже `date` (включительно).
    public func total(through date: Date) -> Int {
        var sum = 0
        for event in events {
            if event.date > date { break }
            sum += event.amount
        }
        return sum
    }

    /// Опыт по ISO-неделям логических дней по возрастанию ключа; недели без опыта в список не входят.
    public func weekly() -> [WeeklyExperience] { weeks }
}

/// Правила опыта (§10.3, решение 10 плана): один проход по фактам, без квадратичных циклов.
public enum Experience {
    public static let passedLessonBonus = 20
    public static let starBonus = 10
    public static let stageBonus = 100
    public static let courseBonus = 1000
    public static let fullDayBonus = 20
    public static let planBonus = 30
    public static let challengeWeekBonus = 100
    public static let challengeWeekAllBonus = 100
    public static let challengeMonthBonus = 500

    /// Опыт за упражнение: `round(минуты чистого времени × 10 × k)`; брошенное — 0. k — по точности с допуском
    /// `LessonScoring.accuracyTolerance`: 100% — 1,5; от 99% — 1,3; от 97% — 1,1; от 96% — 1,0; ниже — 0,5.
    public static func exerciseAmount(_ fact: ExerciseFact) -> Int {
        guard fact.completed else { return 0 }
        let accuracy = fact.accuracy + LessonScoring.accuracyTolerance
        let factor: Double
        switch accuracy {
        case 1...: factor = 1.5
        case 0.99...: factor = 1.3
        case 0.97...: factor = 1.1
        case LessonScoring.passAccuracy...: factor = 1.0
        default: factor = 0.5
        }
        return Int((fact.activeSeconds * 10 * factor / 60).rounded())
    }

    /// Журнал по фактам и готовым испытаниям (`Challenges.evaluate`): так испытания считаются один раз на проверку.
    public static func ledger(_ facts: AchievementFacts, challenges: [ChallengePeriodResult]) -> ExperienceLedger {
        build(Evaluator(facts), challenges: challenges)
    }

    /// Журнал без готовых испытаний: считает их сам.
    public static func ledger(_ facts: AchievementFacts) -> ExperienceLedger {
        Evaluator(facts).experienceLedger()
    }

    static func build(_ ev: Evaluator, challenges: [ChallengePeriodResult]) -> ExperienceLedger {
        let facts = ev.facts
        var raw: [ExperienceEvent] = []
        func add(_ date: Date, _ amount: Int, _ source: ExperienceSource) {
            guard amount > 0 else { return }
            raw.append(ExperienceEvent(date: min(date, facts.now), amount: amount, source: source))
        }

        for fact in ev.completed { add(fact.endedAt, exerciseAmount(fact), .exercise) }
        for lesson in facts.lessonPasses.keys.sorted() {
            add(facts.lessonPasses[lesson]!, passedLessonBonus, .lessonPassed)
        }
        addStars(facts, add)
        for stage in ev.stagesPassed() { add(stage.date, stageBonus, .stagePassed) }
        // Курс пройден — один раз на язык, по более раннему изданию: тот же расчёт, что у ачивки `course.<язык>`.
        for language in Language.allCases {
            if let date = ev.courseDate(language) { add(date, courseBonus, .coursePassed) }
        }
        for day in ev.allDayKeys {
            if let date = ev.goalReachedDate(day: day, factor: 1) { add(date, fullDayBonus, .fullDay) }
        }
        for day in ev.planDoneDays() { add(day.date, planBonus, .planDone) }
        for period in challenges {
            switch period.period {
            case .week:
                for case let date? in period.results.map(\.completedAt) { add(date, challengeWeekBonus, .challengeWeek) }
                if let date = period.allDoneAt { add(date, challengeWeekAllBonus, .challengeWeekAll) }
            case .month:
                for case let date? in period.results.map(\.completedAt) { add(date, challengeMonthBonus, .challengeMonth) }
            }
        }

        let events = raw.enumerated().sorted { ($0.element.date, $0.offset) < ($1.element.date, $1.offset) }.map(\.element)
        var levelUps: [LevelUp] = []
        var level = 1
        var total = 0
        var perWeek: [String: Int] = [:]
        for event in events {
            total += event.amount
            let reached = LevelCurve.level(forExperience: total)
            while level < reached {
                level += 1
                levelUps.append(LevelUp(level: level, date: event.date))
            }
            if let week = ChallengeCalendar.weekKey(ev.logicalDay(of: event.date)) { perWeek[week, default: 0] += event.amount }
        }
        let weeks = perWeek.sorted { $0.key < $1.key }.map { WeeklyExperience(week: $0.key, amount: $0.value) }
        return ExperienceLedger(events: events, levelUps: levelUps, weeks: weeks)
    }

    /// +10 за каждую звезду сверх прежнего максимума урока (убывание и возврат звёзд опыта не дают). Издание 2 — по
    /// шагам изменения звёзд; уроки без шагов (издание 1) — действующие звёзды на дату первого зачёта.
    private static func addStars(_ facts: AchievementFacts, _ add: (Date, Int, ExperienceSource) -> Void) {
        for lesson in Set(facts.lessonStarSteps.keys).union(facts.starsByLesson.keys).sorted() {
            if let steps = facts.lessonStarSteps[lesson], !steps.isEmpty {
                var best = 0
                for step in steps.sorted(by: { $0.date < $1.date }) where step.stars > best {
                    add(step.date, (step.stars - best) * starBonus, .lessonStar)
                    best = step.stars
                }
            } else if let stars = facts.starsByLesson[lesson], stars > 0, let passed = facts.lessonPasses[lesson] {
                add(passed, stars * starBonus, .lessonStar)
            }
        }
    }
}

/// Кривая уровней (решение 11): для уровня L нужно `50·L·(L−1)` опыта всего, на переход L → L+1 — `100·L`.
public enum LevelCurve {
    /// Опыт, всего нужный для уровня `level` (уровень 1 — 0).
    public static func required(_ level: Int) -> Int { 50 * level * (level - 1) }

    /// Наибольший уровень (от 1), порог которого не больше `experience`.
    public static func level(forExperience experience: Int) -> Int {
        guard experience > 0 else { return 1 }
        var level = max(1, Int(((1 + (1 + Double(experience) / 12.5).squareRoot()) / 2).rounded(.down)))
        while required(level + 1) <= experience { level += 1 }
        while level > 1, required(level) > experience { level -= 1 }
        return level
    }

    /// Уровень, опыт сверх его порога и сколько нужно до следующего (`100·L`).
    public static func progress(forExperience experience: Int) -> (level: Int, gained: Int, needed: Int) {
        let level = level(forExperience: experience)
        return (level, max(0, experience) - required(level), 100 * level)
    }
}

/// Звание по уровню: каждые десять уровней, с 50-го — «Легенда».
public enum LevelTitle: Int, CaseIterable, Sendable {
    case novice, apprentice, confident, master, virtuoso, legend

    public static func of(level: Int) -> LevelTitle {
        LevelTitle(rawValue: min(max(level, 0) / 10, 5)) ?? .novice
    }
}

/// Ранг скорости (решение 12): `floor(cpm / 100)` рекорда языка, от «Пешехода» до «Ракеты» (500+).
public enum SpeedRank: Int, CaseIterable, Sendable {
    case pedestrian, cyclist, driver, racer, pilot, rocket

    public static func of(cpm: Double) -> SpeedRank {
        guard cpm >= 0 else { return .pedestrian }
        return SpeedRank(rawValue: Int(min(cpm / 100, 5).rounded(.down))) ?? .pedestrian
    }
}

/// Общие результаты одной проверки: испытания и журнал опыта считаются один раз и переиспользуются ачивками
/// `challenge.*` и `level.*`. Ссылочный тип — `Evaluator` остаётся значением и передаётся по копии.
final class EvaluatorCache {
    var challenges: [ChallengePeriodResult]?
    var ledger: ExperienceLedger?
    /// Сколько раз реально считались (для теста «один раз на проверку»).
    var challengeRuns = 0
    var ledgerRuns = 0
}

extension Evaluator {
    /// Испытания всех периодов (`Challenges.evaluate`) — один расчёт на проверку.
    func challengeResults() -> [ChallengePeriodResult] {
        if let cached = cache.challenges { return cached }
        cache.challengeRuns += 1
        let results = ChallengeEngine(self).evaluateAll()
        cache.challenges = results
        return results
    }

    /// Журнал опыта по готовым испытаниям — один расчёт на проверку.
    func experienceLedger() -> ExperienceLedger {
        if let cached = cache.ledger { return cached }
        cache.ledgerRuns += 1
        let ledger = Experience.build(self, challenges: challengeResults())
        cache.ledger = ledger
        return ledger
    }
}
