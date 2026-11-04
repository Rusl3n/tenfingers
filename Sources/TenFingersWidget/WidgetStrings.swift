import Foundation
import WidgetSnapshot

/// Строки виджета. Язык берётся из снимка (язык интерфейса приложения), а не из системы: строки читаются
/// из `<язык>.lproj` бандла расширения. Нет снимка — язык системы.
struct WidgetStrings: Sendable {
    let language: String

    init(language: String?) {
        if let language, language == "ru" || language == "en" {
            self.language = language
        } else {
            self.language = Locale.preferredLanguages.first?.hasPrefix("ru") == true ? "ru" : "en"
        }
    }

    private var bundle: Bundle {
        Bundle.main.path(forResource: language, ofType: "lproj").flatMap(Bundle.init(path:)) ?? .main
    }

    /// Строка по русскому ключу (исходный язык).
    func text(_ key: String) -> String {
        bundle.localizedString(forKey: key, value: key, table: nil)
    }

    func text(_ key: String, _ args: CVarArg...) -> String {
        String(format: text(key), locale: Locale(identifier: language), arguments: args)
    }

    /// «5 дней», «1 day»: слово по падежу числа.
    func days(_ count: Int) -> String {
        let key = switch WidgetPlural.category(count, language: language) {
        case .one: "день"
        case .few: "дня"
        case .many: "дней"
        }
        return "\(count) \(text(key))"
    }

    func todayLine(_ fire: WidgetSnapshot.FireToday) -> String {
        switch fire {
        case .full: text("Сегодня: день засчитан")
        case .half: text("Сегодня: половина дня")
        case .none: text("Сегодня: ещё нет")
        }
    }

    /// Строка про «Искру» сегодня: засчитана или ещё нет.
    func sparkTodayLine(lit: Bool) -> String {
        lit ? text("Сегодня: засчитано") : text("Сегодня: ещё нет")
    }
}
