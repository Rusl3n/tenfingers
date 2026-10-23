import TypingCore

/// Просьба переключить раскладку на язык упражнения.
enum LayoutPrompt {
    static func switchTo(_ language: Language) -> String {
        language == .ru
            ? String(localized: "Переключите раскладку на русскую")
            : String(localized: "Переключите раскладку на английскую")
    }
}
