import Foundation

/// Расписание и тон напоминаний (значения уже приведены к допустимым пределам или приводятся в `dailyMinutes`).
public struct ReminderConfig: Equatable, Sendable {
    public var mode: ReminderScheduleMode
    /// «Один раз в день»: минута суток.
    public var onceMinute: Int
    /// «3 раза в день»: минуты суток.
    public var thriceMinutes: [Int]
    /// «Каждые N часов»: с `fromHour` до `toHour` включительно, шаг `intervalHours`.
    public var fromHour: Int
    public var toHour: Int
    public var intervalHours: Int
    public var tone: ReminderTone
    /// Нарастающие: каждое следующее напоминание за день настойчивее предыдущего.
    public var escalating: Bool
    /// «Взрослые» тексты — только при включённом «Взрослом юморе».
    public var adultHumor: Bool

    public init(mode: ReminderScheduleMode = .once, onceMinute: Int = 20 * 60,
                thriceMinutes: [Int] = [600, 900, 1200], fromHour: Int = 10, toHour: Int = 21,
                intervalHours: Int = 3, tone: ReminderTone = .mixed, escalating: Bool = false,
                adultHumor: Bool = true) {
        self.mode = mode
        self.onceMinute = onceMinute
        self.thriceMinutes = thriceMinutes
        self.fromHour = fromHour
        self.toHour = toHour
        self.intervalHours = intervalHours
        self.tone = tone
        self.escalating = escalating
        self.adultHumor = adultHumor
    }

    /// Минуты суток напоминаний одного дня: по возрастанию, без повторов, в 0..<1440.
    public func dailyMinutes() -> [Int] {
        func minute(_ value: Int) -> Int { min(max(value, 0), 1439) }
        switch mode {
        case .once:
            return [minute(onceMinute)]
        case .thrice:
            return Set(thriceMinutes.map(minute)).sorted()
        case .interval:
            let from = min(max(fromHour, 0), 23), to = min(max(toHour, 0), 23)
            guard to > from else { return [from * 60] }
            return stride(from: from, through: to, by: min(max(intervalHours, 1), 4)).map { $0 * 60 }
        }
    }
}

/// Что известно о прогрессе на момент планирования.
public struct ReminderSituation: Equatable, Sendable {
    public let streak: Int
    public let todayStatus: DayStatus
    public let minutesLeft: Int

    public init(streak: Int, todayStatus: DayStatus, minutesLeft: Int) {
        self.streak = streak
        self.todayStatus = todayStatus
        self.minutesLeft = minutesLeft
    }
}

public struct PlannedReminder: Equatable, Sendable {
    public let id: String
    public let date: Date
    public let line: ReminderLine
}

/// Чистая часть планировщика: какие напоминания нужно поставить.
public enum ReminderPlanner {
    /// Сколько дней с напоминаниями планируется вперёд.
    public static let horizonDays = 7
    /// Лимит системы — 64 ожидающих уведомления; берётся с запасом.
    public static let maxPending = 60

    /// Идентификатор слота: `reminder.d<i>` (как в прежней схеме одного напоминания в день).
    public static func slotID(_ index: Int) -> String { "reminder.d\(index)" }

    /// Просматривает `horizonDays + 2` календарных дня от `now` (два запасных компенсируют прошедший сегодняшний
    /// момент и дни без напоминаний) и собирает дни с напоминаниями, пока их меньше `horizonDays`;
    /// затем оставляет первые `maxPending` по времени.
    /// - Момент в текущем логическом дне: полный огонь и заморозка — без напоминания, иначе текст по серии и остатку.
    /// - Момент в любом будущем логическом дне: только тексты без чисел.
    /// - Ступень — позиция времени в расписании дня (не среди оставшихся): так 20:00 остаётся «драмой»,
    ///   даже если 10:00 и 15:00 уже прошли.
    public static func plan(now: Date, config: ReminderConfig, situation: ReminderSituation, dayStartHour: Int,
                            calendar: Calendar) -> [PlannedReminder] {
        let minutes = config.dailyMinutes()
        guard !minutes.isEmpty else { return [] }
        let nowDay = LogicalDay.key(for: now, dayStartHour: dayStartHour, calendar: calendar)
        var found: [(date: Date, line: ReminderLine)] = []
        var daysWithReminders = 0
        for offset in 0...(horizonDays + 1) {
            guard daysWithReminders < horizonDays else { break }
            guard let day = calendar.date(byAdding: .day, value: offset, to: now) else { continue }
            var added = false
            for (index, minute) in minutes.enumerated() {
                guard let fire = calendar.date(bySettingHour: minute / 60, minute: minute % 60, second: 0, of: day),
                      fire > now else { continue }
                let dayKey = LogicalDay.key(for: fire, dayStartHour: dayStartHour, calendar: calendar)
                let context: ReminderCatalog.Context
                if dayKey == nowDay {
                    switch situation.todayStatus {
                    case .full, .frozen: continue
                    case .none: context = situation.streak > 0 ? .atRisk(streak: situation.streak) : .fresh
                    case .half: context = .almost(minutes: situation.minutesLeft)
                    }
                } else {
                    context = .later
                }
                let stage = config.escalating ? ReminderStage(rawValue: min(index, 2)) ?? .drama : .soft
                guard let line = ReminderCatalog.pick(context: context, stage: stage, tone: config.tone,
                                                      adultHumor: config.adultHumor, dayKey: dayKey, slot: index)
                else { continue }
                found.append((fire, line))
                added = true
            }
            if added { daysWithReminders += 1 }
        }
        return found.sorted { $0.date < $1.date }.prefix(maxPending).enumerated().map {
            PlannedReminder(id: slotID($0.offset), date: $0.element.date, line: $0.element.line)
        }
    }
}
