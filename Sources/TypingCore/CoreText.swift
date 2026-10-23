import Foundation

/// Переводы строк `TypingCore`. Ключ — русский исходный текст, переводы лежат в `Resources/*.lproj`
/// и ищутся в `CoreResources.bundle`.
enum CoreText {
    /// Перевод на язык системы (язык выбирает бандл, вслед за приложением).
    static func localized(_ key: String) -> String {
        String(localized: String.LocalizationValue(key), bundle: CoreResources.bundle)
    }

    /// Перевод на заданный язык (`"ru"`, `"en"`); без перевода возвращает ключ.
    static func localized(_ key: String, localization: String?) -> String {
        guard let localization else { return localized(key) }
        guard let path = CoreResources.bundle.path(forResource: localization, ofType: "lproj"),
              let bundle = Bundle(path: path) else { return key }
        return bundle.localizedString(forKey: key, value: key, table: nil)
    }
}
