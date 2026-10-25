import Foundation

/// Тексты состояния напоминаний в «Настройки → Напоминания» — чистые функции, чтобы их можно было проверить.
enum ReminderStatus {
    struct Line: Equatable {
        let text: String
        /// Ничего не поставлено при включённых напоминаниях: строка показывается оранжевым.
        let isWarning: Bool
    }

    /// «Запланировано: 7, ближайшее — сегодня в 20:00» по поставленным напоминаниям (`ReminderScheduler.scheduled`);
    /// прошедшие не считаются. Ничего нет — предупреждение: планировщик повторит попытку (или уже исчерпал повторы).
    /// `gaveUp` — повторы исчерпаны: вместо обещания новой попытки — совет открыть приложение позже.
    static func line(scheduled: [Date], now: Date, calendar: Calendar = .current, bundle: Bundle = .main,
                     locale: Locale = .current, gaveUp: Bool = false) -> Line {
        let upcoming = scheduled.filter { $0 > now }.sorted()
        guard let next = upcoming.first else {
            let text = gaveUp
                ? String(localized: "Ничего не запланировано — откройте приложение позже", bundle: bundle, locale: locale)
                : String(localized: "Ничего не запланировано — повторю попытку", bundle: bundle, locale: locale)
            return Line(text: text, isWarning: true)
        }
        let count = upcoming.count
        let when = moment(next, now: now, calendar: calendar, bundle: bundle, locale: locale)
        return Line(text: String(localized: "Запланировано: \(count), ближайшее — \(when)", bundle: bundle,
                                 locale: locale),
                    isWarning: false)
    }

    /// «сегодня в 20:00», «завтра в 02:19», «в четверг в 20:00» (календарные дни, как на часах).
    static func moment(_ date: Date, now: Date, calendar: Calendar, bundle: Bundle, locale: Locale) -> String {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        let time = String(format: "%02d:%02d", parts.hour ?? 0, parts.minute ?? 0)
        if calendar.isDate(date, inSameDayAs: now) {
            return String(localized: "сегодня в \(time)", bundle: bundle, locale: locale)
        }
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: now), calendar.isDate(date, inSameDayAs: tomorrow) {
            return String(localized: "завтра в \(time)", bundle: bundle, locale: locale)
        }
        return switch calendar.component(.weekday, from: date) {
        case 1: String(localized: "в воскресенье в \(time)", bundle: bundle, locale: locale)
        case 2: String(localized: "в понедельник в \(time)", bundle: bundle, locale: locale)
        case 3: String(localized: "во вторник в \(time)", bundle: bundle, locale: locale)
        case 4: String(localized: "в среду в \(time)", bundle: bundle, locale: locale)
        case 5: String(localized: "в четверг в \(time)", bundle: bundle, locale: locale)
        case 6: String(localized: "в пятницу в \(time)", bundle: bundle, locale: locale)
        default: String(localized: "в субботу в \(time)", bundle: bundle, locale: locale)
        }
    }

    /// Система держит меньше напоминаний, чем в плане (`ReminderScheduler.capacity`): «Система принимает только
    /// 1 напоминание — ставлю ближайшее». Склонение — `reminders.limit %lld` в Localizable.stringsdict; без переводов
    /// (запуск без ресурсов) — русская форма.
    static func limitLine(capacity: Int, bundle: Bundle = .main, locale: Locale = .current) -> String {
        guard capacity > 1 else {
            return String(localized: "Система принимает только 1 напоминание — ставлю ближайшее", bundle: bundle,
                          locale: locale)
        }
        let text = String(localized: "reminders.limit \(capacity)", bundle: bundle, locale: locale)
        guard text.hasPrefix("reminders.limit") else { return text }
        let tens = capacity % 100, ones = capacity % 10
        if ones == 1 && tens != 11 {
            return String(localized: "Система принимает только \(capacity) напоминание — ставлю ближайшие",
                          bundle: bundle, locale: locale)
        }
        if (2...4).contains(ones) && !(12...14).contains(tens) {
            return String(localized: "Система принимает только \(capacity) напоминания — ставлю ближайшие",
                          bundle: bundle, locale: locale)
        }
        return String(localized: "Система принимает только \(capacity) напоминаний — ставлю ближайшие",
                      bundle: bundle, locale: locale)
    }

    /// Пояснение мелким шрифтом при пределе 1: следующее ставится только запущенным приложением.
    static func limitNote(capacity: Int, bundle: Bundle = .main, locale: Locale = .current) -> String? {
        guard capacity == 1 else { return nil }
        return String(localized: "Если приложение закрыто, придёт только ближайшее напоминание", bundle: bundle,
                      locale: locale)
    }

    /// Подпись под временем напоминания раньше начала дня: такое напоминание относится к предыдущему логическому дню
    /// (при начале дня в 4:00 напоминание в 02:19 — про вчерашний огонь). `nil` — подпись не нужна.
    static func previousDayNote(minuteOfDay: Int, dayStartHour: Int, bundle: Bundle = .main,
                                locale: Locale = .current) -> String? {
        guard minuteOfDay < dayStartHour * 60 else { return nil }
        return String(localized: "Относится к предыдущему дню: день начинается в \(dayStartHour):00", bundle: bundle,
                      locale: locale)
    }
}
