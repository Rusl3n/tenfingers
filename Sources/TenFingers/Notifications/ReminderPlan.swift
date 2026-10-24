import Foundation
import TypingCore

/// Настройки напоминаний (в `UserDefaults`; по умолчанию выключены): включены ли и расписание с тоном (`ReminderConfig`).
struct ReminderSettings: Equatable {
    var enabled: Bool
    var config: ReminderConfig
}

enum ReminderID {
    /// Идентификаторы прежних версий: при пересчёте удаляются, чтобы не оставить дубли.
    static let legacy = ["reminder.today", "reminder.tomorrow"]
    /// Всё, что планировщик может оставить ожидающим: удаляется перед каждой постановкой.
    /// Идентификаторы прежних версий (`d0…d6`) — часть того же ряда.
    static let all = (0..<ReminderPlanner.maxPending).map(ReminderPlanner.slotID) + legacy
}

/// Что нужно знать о прогрессе, чтобы выбрать текст напоминания.
struct ReminderInputs: Equatable {
    /// Текущая серия (`StreakSummary.current`).
    let streak: Int
    /// Статус сегодняшнего логического дня.
    let todayStatus: DayStatus
    /// Сколько минут не хватает до полного огня (не меньше 1, пока цель не достигнута).
    let minutesLeft: Int

    /// Читает прогресс: серия и статус дня из `StreakCalculator`, остаток до цели — из активности сегодняшнего дня.
    @MainActor
    static func load(snapshot: ProgressSnapshot, now: Date, goalSeconds: Double, dayStartHour: Int,
                     calendar: Calendar = .current) throws -> ReminderInputs {
        let days = try snapshot.dayActivities()
        let today = LogicalDay.key(for: now, dayStartHour: dayStartHour, calendar: calendar)
        let summary = StreakCalculator.summarize(days: days, today: today, goalSeconds: goalSeconds)
        let remaining = max(0, goalSeconds - (days[today]?.activeSeconds ?? 0))
        return ReminderInputs(streak: summary.current, todayStatus: summary.today,
                              minutesLeft: max(1, Int((remaining / 60).rounded(.up))))
    }
}

extension ReminderInputs {
    var situation: ReminderSituation {
        ReminderSituation(streak: streak, todayStatus: todayStatus, minutesLeft: minutesLeft)
    }
}
