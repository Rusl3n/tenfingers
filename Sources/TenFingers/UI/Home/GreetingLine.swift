import Foundation
import TypingCore

/// Приветствие первой строкой «Главной» (фаза 8, §5a): часть суток — по часам Mac, имя — никнейм из профиля.
enum GreetingLine {
    static func part(at date: Date, calendar: Calendar = .current) -> GreetingPart {
        Greeting.part(hour: calendar.component(.hour, from: date))
    }

    /// «Доброе утро, Имя»; пустой никнейм (и из одних пробелов) — «Доброе утро» без запятой.
    static func text(part: GreetingPart, nickname: String, bundle: Bundle = .main,
                     locale: Locale = Formatting.interfaceLocale()) -> String {
        let name = nickname.trimmingCharacters(in: .whitespacesAndNewlines)
        if name.isEmpty { return String(localized: .init(stringLiteral: "greeting.\(part.rawValue)"), bundle: bundle, locale: locale) }
        let format = String(localized: .init(stringLiteral: "greeting.\(part.rawValue).name"), bundle: bundle, locale: locale)
        return String(format: format, locale: locale, name)
    }
}
