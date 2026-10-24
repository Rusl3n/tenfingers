import Foundation
import TypingCore

/// Настройки напоминаний (в `UserDefaults`; по умолчанию выключены).
struct ReminderSettings: Equatable {
    var enabled: Bool
    var hour: Int
    var minute: Int
}

enum ReminderID {
    /// Горизонт планирования: напоминания на ближайшие `horizon` логических дней.
    static let horizon = 7
    static func day(_ index: Int) -> String { "reminder.d\(index)" }
    /// Идентификаторы прежних версий: при пересчёте удаляются, чтобы не оставить дубли.
    static let legacy = ["reminder.today", "reminder.tomorrow"]
    /// Всё, что планировщик может оставить ожидающим: удаляется перед каждой постановкой.
    static let all = (0..<horizon).map(day) + legacy
}

/// Ключи текста напоминания на будущие дни (числа серии к тому времени могут устареть):
/// при серии — «не теряйте серию», без серии — просто «Пора позаниматься».
let genericReminderKey = "Пора позаниматься — не теряйте серию"
let idleReminderKey = "Пора позаниматься"

/// Одно запланированное напоминание: когда и какой текст (ключ локализации и числовые аргументы из `ReminderText`).
struct PlannedReminder: Equatable {
    let id: String
    let date: Date
    let key: String
    let args: [Int]
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

/// Чистая часть планировщика: какие напоминания нужно поставить.
enum ReminderPlan {
    /// Просматривает ближайшие `horizon + 2` календарных дня (два запасных дня компенсируют пропуски: прошедший
    /// сегодняшний момент и день без напоминания) и оставляет первые `horizon` подходящих: момент ещё не наступил и текст нужен.
    /// - Момент в текущем логическом дне — реальный текст `ReminderText.content` (статус дня, серия, остаток);
    ///   для полного огня и заморозки напоминания нет.
    /// - Момент в любом будущем логическом дне — общий текст без чисел (при нулевой серии — без упоминания серии).
    /// Так день, чьё напоминание лежит до `dayStartHour` (например, 02:00 при начале дня в 4:00), не остаётся без него.
    static func requests(now: Date, settings: ReminderSettings, streak: Int, todayStatus: DayStatus,
                         minutesLeft: Int, dayStartHour: Int = SettingsDefault.dayStartHour,
                         calendar: Calendar = .current) -> [PlannedReminder] {
        guard settings.enabled else { return [] }
        let nowDay = LogicalDay.key(for: now, dayStartHour: dayStartHour, calendar: calendar)
        var result: [PlannedReminder] = []
        for offset in 0...(ReminderID.horizon + 1) {
            guard result.count < ReminderID.horizon else { break }
            guard let day = calendar.date(byAdding: .day, value: offset, to: now),
                  let fire = calendar.date(bySettingHour: settings.hour, minute: settings.minute, second: 0, of: day),
                  fire > now else { continue }
            let content: (key: String, args: [Int])?
            if LogicalDay.key(for: fire, dayStartHour: dayStartHour, calendar: calendar) == nowDay {
                content = ReminderText.content(today: todayStatus, streak: streak, minutesLeft: minutesLeft)
            } else {
                content = (key: streak > 0 ? genericReminderKey : idleReminderKey, args: [])
            }
            guard let content else { continue }
            result.append(PlannedReminder(id: ReminderID.day(result.count), date: fire,
                                          key: content.key, args: content.args))
        }
        return result
    }
}

/// Текст уведомления: ключ из `ReminderText` переводится и подставляются числа.
enum ReminderMessage {
    static func text(key: String, args: [Int], bundle: Bundle = .main) -> String {
        let format = bundle.localizedString(forKey: key, value: key, table: nil)
        return args.isEmpty ? format : String(format: format, arguments: args.map { $0 as CVarArg })
    }
}
