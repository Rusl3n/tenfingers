import Foundation

/// Тексты метрик дней «Искра» и «Цель»: на главной и на карточке «Мой прогресс».
enum DayMetricsText {
    /// «Искра: 12 дней подряд · всего 40» (метрика `visit*` в ядре).
    static func spark(current: Int, total: Int, bundle: Bundle = .main, locale: Locale? = nil) -> String {
        let locale = locale ?? Formatting.interfaceLocale(bundle: bundle)
        let days = Formatting.days(current, bundle: bundle, locale: locale)
        return String(localized: "Искра: \(days) подряд · всего \(total)", bundle: bundle, locale: locale)
    }

    /// «рекорд 20 дней · всего 40» — подпись под числом в блоке «Искры».
    static func sparkRecord(longest: Int, total: Int, bundle: Bundle = .main, locale: Locale? = nil) -> String {
        let locale = locale ?? Formatting.interfaceLocale(bundle: bundle)
        let days = Formatting.days(longest, bundle: bundle, locale: locale)
        return String(localized: "рекорд \(days) · всего \(total)", bundle: bundle, locale: locale)
    }

    /// «Цель: 5 дней подряд · всего 22».
    static func goals(current: Int, total: Int, bundle: Bundle = .main, locale: Locale? = nil) -> String {
        let locale = locale ?? Formatting.interfaceLocale(bundle: bundle)
        let days = Formatting.days(current, bundle: bundle, locale: locale)
        return String(localized: "Цель: \(days) подряд · всего \(total)", bundle: bundle, locale: locale)
    }
}
