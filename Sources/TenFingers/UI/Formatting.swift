import Foundation

enum Formatting {
    /// «11 ч 40 мин», «2 мин».
    static func duration(_ seconds: Double) -> String {
        let minutes = Int(seconds) / 60
        let hours = minutes / 60
        let rest = minutes % 60
        return hours > 0 ? String(localized: "\(hours) ч \(rest) мин") : String(localized: "\(minutes) мин")
    }

    /// «01:12».
    static func clock(_ seconds: Double) -> String {
        let total = Int(seconds)
        return String(format: "%02d:%02d", total / 60, total % 60)
    }

    /// «97,4%» (разделитель — по региону пользователя). `rounding: .down` отбрасывает лишние знаки:
    /// 99,49% — «99,4%», а не «99,5%» (результат рядом с порогом не должен выглядеть достигшим его).
    static func percent(_ value: Double, rounding: FloatingPointRoundingRule? = nil, locale: Locale = .current) -> String {
        let value = rounding.map { rule in
            // Поправка: 0,989 × 1000 в двоичной арифметике чуть меньше 989 и без неё округлилось бы вниз до 988.
            let nudge: Double = switch rule {
            case .down, .towardZero: 1e-9
            case .up, .awayFromZero: -1e-9
            default: 0
            }
            return (value * 1000 + nudge).rounded(rule) / 1000
        } ?? value
        return (value * 100).formatted(.number.precision(.fractionLength(1)).locale(locale)) + "%"
    }
}

extension Formatting {
    /// Язык, на котором показан интерфейс (первая из локализаций приложения, выбранная системой).
    static func interfaceLocale(bundle: Bundle = .main) -> Locale {
        Locale(identifier: bundle.preferredLocalizations.first ?? "en")
    }

    /// «1 день», «2 дня», «5 дней»: склонение задаёт Localizable.stringsdict (ключ `streak.days %lld`).
    /// Правило множественного числа берётся из языка, на котором показан интерфейс (а не из региона системы).
    static func days(_ count: Int, bundle: Bundle = .main, locale: Locale? = nil) -> String {
        let locale = locale ?? interfaceLocale(bundle: bundle)
        let text = String(localized: "streak.days \(count)", bundle: bundle, locale: locale)
        // Переводов нет (запуск без ресурсов приложения): склоняем по-русски, как исходный язык интерфейса.
        return text.hasPrefix("streak.days") ? russianDays(count, bundle: bundle) : text
    }

    /// «1 день», «3 дня», «5 дней», «11 дней», «21 день» (запасной вариант без `.stringsdict`).
    private static func russianDays(_ count: Int, bundle: Bundle) -> String {
        let tens = abs(count) % 100, ones = abs(count) % 10
        let word = if ones == 1 && tens != 11 { String(localized: "день", bundle: bundle) }
            else if (2...4).contains(ones) && !(12...14).contains(tens) { String(localized: "дня", bundle: bundle) }
            else { String(localized: "дней", bundle: bundle) }
        return "\(count) \(word)"
    }
}

extension Formatting {
    /// «Получена 21 ачивка за прошлые занятия», «Получено 5 ачивок…»: склонение задаёт Localizable.stringsdict
    /// (ключ `achievements.backfill %lld`), правило — по языку интерфейса, как у `days`.
    static func backfillSummary(_ count: Int, bundle: Bundle = .main, locale: Locale? = nil) -> String {
        let locale = locale ?? interfaceLocale(bundle: bundle)
        let text = String(localized: "achievements.backfill \(count)", bundle: bundle, locale: locale)
        guard text.hasPrefix("achievements.backfill") else { return text }
        // Переводов нет (запуск без ресурсов приложения): склоняем по-русски.
        let tens = abs(count) % 100, ones = abs(count) % 10
        if ones == 1 && tens != 11 {
            return String(localized: "Получена \(count) ачивка за прошлые занятия", bundle: bundle)
        }
        if (2...4).contains(ones) && !(12...14).contains(tens) {
            return String(localized: "Получено \(count) ачивки за прошлые занятия", bundle: bundle)
        }
        return String(localized: "Получено \(count) ачивок за прошлые занятия", bundle: bundle)
    }
}

extension Formatting {
    /// «1 ошибка», «2 ошибки», «5 ошибок» (`errors.count %lld` в Localizable.stringsdict; без переводов —
    /// русская форма, как у `days`).
    static func errors(_ count: Int, bundle: Bundle = .main, locale: Locale? = nil) -> String {
        let locale = locale ?? interfaceLocale(bundle: bundle)
        let text = String(localized: "errors.count \(count)", bundle: bundle, locale: locale)
        guard text.hasPrefix("errors.count") else { return text }
        // Переводов нет (запуск без ресурсов приложения): склоняем по-русски.
        let tens = abs(count) % 100, ones = abs(count) % 10
        let word = if ones == 1 && tens != 11 { String(localized: "ошибка", bundle: bundle) }
            else if (2...4).contains(ones) && !(12...14).contains(tens) { String(localized: "ошибки", bundle: bundle) }
            else { String(localized: "ошибок", bundle: bundle) }
        return "\(count) \(word)"
    }

    /// «не больше 1 ошибки», «не больше 3 ошибок» (`errors.atMost %lld` в Localizable.stringsdict; без переводов —
    /// русская форма, как у `days`).
    static func atMostErrors(_ count: Int, bundle: Bundle = .main, locale: Locale? = nil) -> String {
        let locale = locale ?? interfaceLocale(bundle: bundle)
        let text = String(localized: "errors.atMost \(count)", bundle: bundle, locale: locale)
        guard text.hasPrefix("errors.atMost") else { return text }
        // Переводов нет (запуск без ресурсов приложения): склоняем по-русски.
        let tens = abs(count) % 100, ones = abs(count) % 10
        return ones == 1 && tens != 11
            ? String(localized: "не больше \(count) ошибки", bundle: bundle)
            : String(localized: "не больше \(count) ошибок", bundle: bundle)
    }

    /// «не больше чем с 1 ошибкой», «не больше чем с 2 ошибками» (`errors.withAtMost %lld`; без переводов — русская форма).
    static func withAtMostErrors(_ count: Int, bundle: Bundle = .main, locale: Locale? = nil) -> String {
        let locale = locale ?? interfaceLocale(bundle: bundle)
        let text = String(localized: "errors.withAtMost \(count)", bundle: bundle, locale: locale)
        guard text.hasPrefix("errors.withAtMost") else { return text }
        let tens = abs(count) % 100, ones = abs(count) % 10
        return ones == 1 && tens != 11
            ? String(localized: "не больше чем с \(count) ошибкой", bundle: bundle)
            : String(localized: "не больше чем с \(count) ошибками", bundle: bundle)
    }
}
