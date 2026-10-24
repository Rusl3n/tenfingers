import Foundation

public enum DayStatus: String, Codable, Sendable {
    case full, half, frozen, none
}

public struct DayActivity: Equatable, Sendable {
    public let activeSeconds: Double
    public let completedExercises: Int
    /// Дневная цель (секунды), действовавшая в этот день (`DayRecord.goalSeconds`); `nil` — неизвестна
    /// (дни до поколения схемы 5), тогда день считается по текущей цели. Для сегодняшнего дня не используется:
    /// сегодня всегда действует текущая цель.
    public let goalSeconds: Double?
    public init(activeSeconds: Double, completedExercises: Int, goalSeconds: Double? = nil) {
        self.activeSeconds = activeSeconds
        self.completedExercises = completedExercises
        self.goalSeconds = goalSeconds
    }
}

public struct StreakSummary: Equatable, Sendable {
    /// Дней подряд со статусом full/half/frozen, заканчивая вчера (или сегодня, если сегодня уже занимались).
    public let current: Int
    /// Полных дней подряд (отсчёт для заморозок), на конец того же периода.
    public let fullInRow: Int
    /// Сколько полных дней внутри текущей серии.
    public let fullInCurrent: Int
    public let freezes: Int
    public let longest: Int
    /// Статус сегодня (none — ещё не занимались).
    public let today: DayStatus
    /// Статусы всех дней от первого занятия до сегодня. Ключ — логический день "yyyy-MM-dd".
    public let statuses: [String: DayStatus]
    /// «Заходил»: дни с хотя бы одним завершённым упражнением. Подряд (без заморозок), рекорд и всего.
    public let visitCurrent: Int
    public let visitLongest: Int
    public let visitTotal: Int
    /// «Цель»: полные дни по цели того дня. Подряд (без заморозок), рекорд и всего.
    public let goalCurrent: Int
    public let goalLongest: Int
    public let goalTotal: Int

    public init(current: Int, fullInRow: Int, fullInCurrent: Int, freezes: Int, longest: Int,
                today: DayStatus, statuses: [String: DayStatus],
                visitCurrent: Int = 0, visitLongest: Int = 0, visitTotal: Int = 0,
                goalCurrent: Int = 0, goalLongest: Int = 0, goalTotal: Int = 0) {
        self.current = current
        self.fullInRow = fullInRow
        self.fullInCurrent = fullInCurrent
        self.freezes = freezes
        self.longest = longest
        self.today = today
        self.statuses = statuses
        self.visitCurrent = visitCurrent
        self.visitLongest = visitLongest
        self.visitTotal = visitTotal
        self.goalCurrent = goalCurrent
        self.goalLongest = goalLongest
        self.goalTotal = goalTotal
    }
}

/// Серия считается заново по всей истории: заморозки не хранятся, а выводятся.
public enum StreakCalculator {
    public static let maxFreezes = 2
    public static let fullDaysPerFreeze = 7

    public static func status(_ activity: DayActivity?, goalSeconds: Double) -> DayStatus {
        guard let activity else { return .none }
        if activity.activeSeconds >= goalSeconds && activity.completedExercises > 0 { return .full }
        if activity.completedExercises > 0 { return .half }
        return .none
    }

    /// `goalSeconds` — текущая дневная цель: действует сегодня и для прошлых дней без записанной цели
    /// (`DayActivity.goalSeconds == nil`).
    public static func summarize(days: [String: DayActivity], today: String, goalSeconds: Double) -> StreakSummary {
        let keys = days.filter { $0.value.completedExercises > 0 }.keys.sorted()
        guard let first = keys.first, first <= today else {
            return StreakSummary(current: 0, fullInRow: 0, fullInCurrent: 0, freezes: 0, longest: 0,
                                 today: .none, statuses: [:])
        }
        var statuses: [String: DayStatus] = [:]
        var streak = 0, fullInRow = 0, fullInCurrent = 0, freezes = 0, longest = 0
        var visitRun = 0, visitLongest = 0, visitTotal = 0, goalRun = 0, goalLongest = 0, goalTotal = 0
        for day in dayKeys(from: first, to: today) {
            // Прошлый день — по цели того дня (если записана), сегодня — по текущей.
            let goal = day < today ? days[day]?.goalSeconds ?? goalSeconds : goalSeconds
            let raw = status(days[day], goalSeconds: goal)
            // «Заходил» и «Цель»: заморозки не действуют; сегодняшний день без зачёта серию не обрывает.
            let isToday = day == today
            if raw == .full || raw == .half { visitRun += 1; visitTotal += 1 } else if !isToday { visitRun = 0 }
            if raw == .full { goalRun += 1; goalTotal += 1 } else if !isToday { goalRun = 0 }
            visitLongest = max(visitLongest, visitRun)
            goalLongest = max(goalLongest, goalRun)
            if day == today && raw == .none {
                statuses[day] = DayStatus.none   // сегодня ещё можно успеть
                break
            }
            switch raw {
            case .full:
                streak += 1
                fullInCurrent += 1
                fullInRow += 1
                if fullInRow % fullDaysPerFreeze == 0 { freezes = min(maxFreezes, freezes + 1) }
                statuses[day] = .full
            case .half:
                streak += 1
                fullInRow = 0
                statuses[day] = .half
            case .none, .frozen:
                if streak > 0 && freezes > 0 {
                    freezes -= 1
                    streak += 1
                    fullInRow = 0
                    statuses[day] = .frozen
                } else {
                    streak = 0
                    fullInRow = 0
                    fullInCurrent = 0
                    statuses[day] = DayStatus.none
                }
            }
            longest = max(longest, streak)
        }
        return StreakSummary(current: streak, fullInRow: fullInRow, fullInCurrent: fullInCurrent,
                             freezes: freezes, longest: longest, today: statuses[today] ?? .none,
                             statuses: statuses,
                             visitCurrent: visitRun, visitLongest: visitLongest, visitTotal: visitTotal,
                             goalCurrent: goalRun, goalLongest: goalLongest, goalTotal: goalTotal)
    }

    /// Все ключи дней от `from` до `to` включительно (григорианский календарь, UTC — ключи уже логические даты).
    public static func dayKeys(from: String, to: String) -> [String] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        guard var date = parse(from, calendar), let end = parse(to, calendar), date <= end else { return [] }
        var result: [String] = []
        while date <= end {
            let c = calendar.dateComponents([.year, .month, .day], from: date)
            result.append(pad(c.year ?? 0, 4) + "-" + pad(c.month ?? 0, 2) + "-" + pad(c.day ?? 0, 2))
            date = calendar.date(byAdding: .day, value: 1, to: date)!
        }
        return result
    }

    /// Ключ дня, сдвинутый на `offset` дней (может быть отрицательным). Некорректный ключ возвращается как есть.
    public static func dayKey(_ key: String, offset: Int) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        guard let date = parse(key, calendar), let shifted = calendar.date(byAdding: .day, value: offset, to: date) else {
            return key
        }
        let c = calendar.dateComponents([.year, .month, .day], from: shifted)
        return pad(c.year ?? 0, 4) + "-" + pad(c.month ?? 0, 2) + "-" + pad(c.day ?? 0, 2)
    }

    private static func pad(_ value: Int, _ width: Int) -> String {
        let digits = String(value)
        return String(repeating: "0", count: max(0, width - digits.count)) + digits
    }

    private static func parse(_ key: String, _ calendar: Calendar) -> Date? {
        let parts = key.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
    }
}
