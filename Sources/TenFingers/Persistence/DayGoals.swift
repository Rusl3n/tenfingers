import Foundation
import os
import SwiftData
import TypingCore

private let dayGoalsLog = Logger(subsystem: "local.tenfingers", category: "dayGoals")

/// Цель дня за каждым днём (`DayRecord.goalSeconds`, поколение схемы 5): прошлый день считается по цели,
/// которая действовала в нём, поэтому смена цели в настройках не меняет прошлые огоньки. Сегодняшний день
/// всегда следует текущей цели.
@MainActor
enum DayGoals {
    /// Дням до `today` включительно без записанной цели записывает `goalSeconds` — цель, действующую сейчас:
    /// лучшее, что о них известно. Сегодняшний день тоже получает её: так день, начатый до обновления или
    /// пришедший из файла, не остаётся без цели после полуночи (сегодня всё равно считается по текущей цели,
    /// а смена цели держит запись сегодняшнего дня актуальной). Дни с целью не трогаются, поэтому повторный
    /// вызов ничего не меняет. Возвращает число заполненных дней. Ошибка сохранения откатывает контекст.
    @discardableResult
    static func backfill(context: ModelContext, goalSeconds: Double, today: String) throws -> Int {
        let descriptor = FetchDescriptor<DayRecord>(
            predicate: #Predicate { $0.goalSeconds == nil && $0.logicalDay <= today })
        let days = try context.fetch(descriptor)
        guard !days.isEmpty else { return 0 }
        for day in days { day.goalSeconds = goalSeconds }
        try save(context)
        return days.count
    }

    /// Цель сменили в настройках с `previousGoalSeconds` на `goalSeconds`. Сначала дни без цели (записанные до
    /// поколения 5 и ещё не заполненные — например, вчерашний, если приложение пережило полночь без перезапуска)
    /// получают прежнюю цель: она в них и действовала. Затем запись сегодняшнего дня (если сегодня уже занимались)
    /// следует новой цели; прошлые дни остаются со своей.
    static func goalChanged(context: ModelContext, from previousGoalSeconds: Double, to goalSeconds: Double,
                            today: String) throws {
        try backfill(context: context, goalSeconds: previousGoalSeconds, today: today)
        let descriptor = FetchDescriptor<DayRecord>(predicate: #Predicate { $0.logicalDay == today })
        guard let record = try context.fetch(descriptor).first, record.goalSeconds != goalSeconds else { return }
        record.goalSeconds = goalSeconds
        try save(context)
    }

    /// При запуске и после загрузки прогресса из файла: цель и час начала дня — из настроек. Ошибка только
    /// пишется в журнал: незаполненный день считается по текущей цели, как и раньше.
    static func backfillLogging(context: ModelContext, defaults: UserDefaults = .standard, now: Date = .now,
                                calendar: Calendar = .current) {
        let today = today(defaults: defaults, now: now, calendar: calendar)
        do {
            let filled = try backfill(context: context, goalSeconds: StoredSettings.dailyGoalSeconds(defaults), today: today)
            if filled > 0 { dayGoalsLog.info("Day goals backfilled: \(filled, privacy: .public)") }
        } catch {
            dayGoalsLog.error("Day goals backfill failed: \(String(describing: error), privacy: .public)")
        }
    }

    /// Смена «Дневной цели» в настройках: прежняя цель — из `onChange`, новая и час начала дня — из настроек.
    static func goalChangedLogging(context: ModelContext, previousGoalSeconds: Double,
                                   defaults: UserDefaults = .standard, now: Date = .now, calendar: Calendar = .current) {
        do {
            try goalChanged(context: context, from: previousGoalSeconds, to: StoredSettings.dailyGoalSeconds(defaults),
                            today: today(defaults: defaults, now: now, calendar: calendar))
        } catch {
            dayGoalsLog.error("Day goal update failed: \(String(describing: error), privacy: .public)")
        }
    }

    /// Сегодняшний логический день по часу начала дня из настроек.
    private static func today(defaults: UserDefaults, now: Date, calendar: Calendar) -> String {
        LogicalDay.key(for: now, dayStartHour: StoredSettings.dayStartHour(defaults), calendar: calendar)
    }

    private static func save(_ context: ModelContext) throws {
        do { try context.save() } catch {
            context.rollback()
            throw error
        }
    }
}
