import Foundation

/// День для статистики и серии: начинается не в полночь, а в `dayStartHour`.
public enum LogicalDay {
    /// Считается по календарным полям, а не вычитанием часов, поэтому переход на летнее время не сдвигает день.
    public static func key(for date: Date, dayStartHour: Int, calendar: Calendar = .current) -> String {
        let hour = calendar.component(.hour, from: date)
        let startOfDay = calendar.startOfDay(for: date)
        let day = hour < dayStartHour
            ? calendar.date(byAdding: .day, value: -1, to: startOfDay) ?? startOfDay
            : startOfDay
        let parts = calendar.dateComponents([.year, .month, .day], from: day)
        return format(parts.year ?? 0, width: 4) + "-" + format(parts.month ?? 0, width: 2) + "-"
            + format(parts.day ?? 0, width: 2)
    }

    private static func format(_ value: Int, width: Int) -> String {
        let digits = String(value)
        return String(repeating: "0", count: max(0, width - digits.count)) + digits
    }
}
