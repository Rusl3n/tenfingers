import Foundation

/// Тексты метрик дней «Заходил» и «Цель»: на главной и на карточке «Мой прогресс».
enum DayMetricsText {
    /// «Заходил: 12 дней подряд · всего 40».
    static func visits(current: Int, total: Int, bundle: Bundle = .main, locale: Locale? = nil) -> String {
        let locale = locale ?? Formatting.interfaceLocale(bundle: bundle)
        let days = Formatting.days(current, bundle: bundle, locale: locale)
        return String(localized: "Заходил: \(days) подряд · всего \(total)", bundle: bundle, locale: locale)
    }

    /// «Цель: 5 дней подряд · всего 22».
    static func goals(current: Int, total: Int, bundle: Bundle = .main, locale: Locale? = nil) -> String {
        let locale = locale ?? Formatting.interfaceLocale(bundle: bundle)
        let days = Formatting.days(current, bundle: bundle, locale: locale)
        return String(localized: "Цель: \(days) подряд · всего \(total)", bundle: bundle, locale: locale)
    }
}
