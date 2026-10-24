import Foundation

/// Язык интерфейса (§3 спецификации фазы 5). Пишет `AppleLanguages` в домен приложения; действует после перезапуска.
/// Язык курса (`activeLanguage`) — отдельная настройка.
enum InterfaceLanguage: String, CaseIterable, Identifiable {
    case system, ru, en

    var id: String { rawValue }

    /// «Русский» и «English» — родные названия, без перевода (в английском интерфейсе тоже «Русский»).
    /// Кириллица записана кодами символов, чтобы сторож `LocalizationTests` не требовал для неё перевода.
    var title: String {
        switch self {
        case .system: String(localized: "Как в системе")
        case .ru: "\u{420}\u{443}\u{441}\u{441}\u{43A}\u{438}\u{439}"
        case .en: "English"
        }
    }

    static let appleLanguagesKey = "AppleLanguages"

    /// Нет ключа или мусор — `.system`.
    static func stored(_ defaults: UserDefaults = .standard) -> InterfaceLanguage {
        defaults.string(forKey: SettingsKey.interfaceLanguage).flatMap(InterfaceLanguage.init(rawValue:)) ?? .system
    }

    /// Пишет `interfaceLanguage` и `AppleLanguages` (["ru"] / ["en"]); для `.system` удаляет `AppleLanguages`.
    func apply(to defaults: UserDefaults = .standard) {
        defaults.set(rawValue, forKey: SettingsKey.interfaceLanguage)
        switch self {
        case .system: defaults.removeObject(forKey: Self.appleLanguagesKey)
        case .ru: defaults.set(["ru"], forKey: Self.appleLanguagesKey)
        case .en: defaults.set(["en"], forKey: Self.appleLanguagesKey)
        }
    }

    /// Выбор на момент запуска (читается один раз; `TenFingersApp.init` обращается к нему первым).
    @MainActor static let atLaunch: InterfaceLanguage = stored()

    static func needsRestart(selected: InterfaceLanguage, atLaunch: InterfaceLanguage) -> Bool { selected != atLaunch }
}
