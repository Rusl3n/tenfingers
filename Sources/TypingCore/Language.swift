public enum Language: String, Codable, CaseIterable, Sendable, Identifiable {
    case ru, en

    public var id: String { rawValue }

    /// Название языка на языке системы.
    public var displayName: String { CoreText.localized(displayNameKey) }

    /// Ключ перевода: русское название языка.
    var displayNameKey: String {
        switch self {
        case .ru: "Русский"
        case .en: "English"
        }
    }

    public var shortName: String { rawValue.uppercased() }

    public var letters: Set<Character> {
        switch self {
        case .ru: Set("абвгдеёжзийклмнопрстуфхцчшщъыьэюя")
        case .en: Set("abcdefghijklmnopqrstuvwxyz")
        }
    }

    /// Порядок открытия букв в адаптивной тренировке — по частоте в языке.
    public var adaptiveOrder: [Character] {
        switch self {
        case .ru: Array("оеаинтсрвлкмдпуяыьгзбчйхжшюцщэфъё")
        case .en: Array("etaoinsrhldcumfpgwybvkxjqz")
        }
    }

    /// Код языка источника ввода macOS: "ru", "en-US" и т. п.
    public init?(inputSourceLanguage code: String) {
        self.init(rawValue: String(code.prefix(2)).lowercased())
    }
}
