public enum ReminderText {
    /// nil — напоминание не нужно (сегодня полный огонь или заморозка).
    /// Ключи — русские строки для локализации в приложении: возвращает (ключ, аргументы).
    public static func content(today: DayStatus, streak: Int, minutesLeft: Int) -> (key: String, args: [Int])? {
        switch today {
        case .none:
            streak > 0
                ? (key: "Серия %lld дн. под угрозой", args: [streak])
                : (key: "Пора позаниматься: начните новую серию", args: [])
        case .half:
            (key: "До полного огня осталось %lld мин", args: [minutesLeft])
        case .full, .frozen:
            nil
        }
    }
}
