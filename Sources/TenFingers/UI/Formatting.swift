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

    /// «97,4%» (разделитель — по региону пользователя).
    static func percent(_ value: Double, locale: Locale = .current) -> String {
        (value * 100).formatted(.number.precision(.fractionLength(1)).locale(locale)) + "%"
    }
}
