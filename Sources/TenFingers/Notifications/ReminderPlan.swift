import Foundation
import TypingCore

/// Настройки напоминаний (в `UserDefaults`; по умолчанию выключены): включены ли и расписание с тоном (`ReminderConfig`).
struct ReminderSettings: Equatable {
    var enabled: Bool
    var config: ReminderConfig
}

enum ReminderID {
    /// Все напоминания приложения, нынешние (`ReminderPlanner.id`) и прежних версий (`reminder.d<i>`,
    /// `reminder.today`, `reminder.tomorrow`), начинаются так; чужих ожидающих уведомлений нет.
    static let prefix = "reminder."

    /// Пробное напоминание («Проверить напоминание»): в план не входит, пересчёт его не трогает.
    static let test = "reminder.test"

    static func isReminder(_ id: String) -> Bool { id.hasPrefix(prefix) }

    /// Напоминание из плана (нынешнего или прежних версий), а не пробное.
    static func isPlanned(_ id: String) -> Bool { isReminder(id) && id != test }
}

/// Что изменить в ожидающих уведомлениях, чтобы они совпали с планом: удалить напоминания, которых в плане нет
/// (в том числе с идентификаторами прежних версий), и поставить новые или изменившиеся (время, заголовок, текст;
/// уведомление с тем же идентификатором система заменяет). Пробное (`ReminderID.test`) не трогается.
/// Совпадающие не трогаются: каждый запрос к системе
/// расходует её лимит частоты, а лишние она отбрасывает («Too many requests»).
struct ReminderDiff: Equatable {
    let remove: [String]
    let add: [ReminderNotification]

    var isEmpty: Bool { remove.isEmpty && add.isEmpty }

    static func make(pending: [ReminderNotification], planned: [ReminderNotification]) -> ReminderDiff {
        let current = Dictionary(pending.filter { ReminderID.isPlanned($0.id) }.map { ($0.id, $0) },
                                 uniquingKeysWith: { first, _ in first })
        let wanted = Set(planned.map(\.id))
        return ReminderDiff(remove: current.keys.filter { !wanted.contains($0) }.sorted(),
                            add: planned.filter { current[$0.id] != $0 })
    }
}

/// Что нужно знать о прогрессе, чтобы выбрать текст напоминания.
struct ReminderInputs: Equatable {
    /// Текущая серия (`StreakSummary.current`).
    let streak: Int
    /// Статус сегодняшнего логического дня.
    let todayStatus: DayStatus
    /// Сколько минут не хватает до полного огня (не меньше 1, пока цель не достигнута).
    let minutesLeft: Int
    /// «Починка» открыта (`StreakSummary.repairPending`): спасаемая серия и минуты до двойной цели.
    var repair: RepairSituation? = nil

    /// Читает прогресс: серия и статус дня из `StreakCalculator`, остаток до цели — из активности сегодняшнего дня.
    @MainActor
    static func load(snapshot: ProgressSnapshot, now: Date, goalSeconds: Double, dayStartHour: Int,
                     calendar: Calendar = .current) throws -> ReminderInputs {
        let days = try snapshot.dayActivities()
        let today = LogicalDay.key(for: now, dayStartHour: dayStartHour, calendar: calendar)
        let summary = StreakCalculator.summarize(days: days, today: today, goalSeconds: goalSeconds)
        let remaining = max(0, goalSeconds - (days[today]?.activeSeconds ?? 0))
        let repair = summary.repairPending
            ? RepairSituation(streak: summary.repairStreak,
                              minutesLeft: max(1, Int((summary.repairNeedSeconds / 60).rounded(.up))))
            : nil
        return ReminderInputs(streak: summary.current, todayStatus: summary.today,
                              minutesLeft: max(1, Int((remaining / 60).rounded(.up))), repair: repair)
    }
}

extension ReminderInputs {
    var situation: ReminderSituation {
        ReminderSituation(streak: streak, todayStatus: todayStatus, minutesLeft: minutesLeft, repair: repair)
    }
}

/// Дата напоминания в триггере системы (`UNCalendarNotificationTrigger`) — компоненты до минуты по календарю;
/// обратное преобразование нужно, чтобы сравнить ожидающие уведомления с планом (`ReminderDiff`).
enum ReminderTrigger {
    static func components(for date: Date, calendar: Calendar) -> DateComponents {
        calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
    }

    static func date(from components: DateComponents, calendar: Calendar) -> Date? {
        calendar.date(from: components)
    }
}
