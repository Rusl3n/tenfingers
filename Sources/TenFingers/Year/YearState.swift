import Foundation
import SwiftData
import TypingCore

/// Снимок «года» (6e): опыт и уровень, испытания текущей недели и месяца, история выполненных испытаний, серия с
/// починкой. Всё выводится из истории одним проходом по фактам (`AchievementService.facts()`); ничего не хранится.
struct YearState: Equatable {
    let ledger: ExperienceLedger
    let level: Int
    let title: LevelTitle
    /// Опыт сверх порога текущего уровня и сколько нужно на переход к следующему (`100·L`).
    let gained: Int
    let needed: Int
    /// Испытания недели и месяца, в которые входит сегодняшний логический день; `nil` — занятий ещё не было.
    let week: ChallengePeriodResult?
    let month: ChallengePeriodResult?
    /// Периоды хотя бы с одним выполненным испытанием, новые сверху (при равном начале месяц выше недели).
    let history: [ChallengePeriodResult]
    let streak: StreakSummary
    /// Сегодняшний логический день (`yyyy-MM-dd`).
    let today: String

    /// Снимок по готовым фактам: испытания считаются один раз и идут и в журнал опыта.
    static func build(_ facts: AchievementFacts) -> YearState {
        let challenges = Challenges.evaluate(facts)
        let ledger = Experience.ledger(facts, challenges: challenges)
        let progress = LevelCurve.progress(forExperience: ledger.total)
        let today = facts.today ?? ""
        let goal = facts.currentGoalSeconds ?? Double(Challenges.defaultGoalMinutes * 60)
        return YearState(
            ledger: ledger, level: progress.level, title: LevelTitle.of(level: progress.level),
            gained: progress.gained, needed: progress.needed,
            week: challenges.first { $0.period == .week(containing: today) },
            month: challenges.first { $0.period == .month(containing: today) },
            history: challenges.filter { $0.results.contains { $0.completedAt != nil } }.reversed(),
            streak: StreakCalculator.summarize(days: facts.days, today: today, goalSeconds: goal),
            today: today)
    }
}

/// Ключ кэша снимка года (решение 16): число сессий, последняя `endedAt`, сегодняшний логический день и текущая цель.
struct YearStateKey: Equatable {
    let sessions: Int
    let lastEndedAt: Date?
    let today: String
    let goalSeconds: Double
}

/// Загрузчик снимка года: факты — через `AchievementService` (общий кэш упражнений), снимок — в кэше фактов, пока
/// история, день и цель те же. Минутный таймер главной не пересчитывает опыт, если ничего не менялось.
@MainActor
struct YearLoader {
    let context: ModelContext
    let service: AchievementService

    init(context: ModelContext, service: AchievementService? = nil) {
        self.context = context
        self.service = service ?? .live(context: context)
    }

    func state() throws -> YearState {
        let key = try service.yearKey()
        return try service.cache.yearState(key: key) {
            // Факты только что прошедшей проверки ачивок (тот же ключ) не собираются второй раз.
            YearState.build(try service.cache.takeFacts(for: key) ?? service.facts())
        }
    }
}
