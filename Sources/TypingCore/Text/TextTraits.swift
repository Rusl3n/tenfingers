import Foundation

/// Свойства набранного текста (`SessionRecord.textTraits`, поколение схемы 6; спецификация фазы 6 §8.4).
public struct TextTraits: OptionSet, Hashable, Sendable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }

    public static let capitals = TextTraits(rawValue: 1)
    public static let punctuation = TextTraits(rawValue: 2)
    public static let digits = TextTraits(rawValue: 4)
    /// Связный текст: отрывок библиотеки, свой текст (с 6b — ещё предложения и тексты курса).
    public static let connected = TextTraits(rawValue: 8)

    /// Свойства по символам: заглавная — `isUppercase`; цифра — ASCII 0–9; знак — `isPunctuation || isSymbol`.
    /// Пробелы и буквы в нижнем регистре ничего не добавляют.
    public static func of<S: Sequence>(_ text: S) -> TextTraits where S.Element == Character {
        var traits: TextTraits = []
        for character in text {
            if character.isUppercase { traits.insert(.capitals) }
            else if character.isASCII && character.isWholeNumber { traits.insert(.digits) }
            else if character.isPunctuation || character.isSymbol { traits.insert(.punctuation) }
        }
        return traits
    }

    /// Связный ли текст по источнику (`SessionRecord.source`): `library:<id>` и `custom`.
    public static func connected(source: String?) -> TextTraits {
        guard let source else { return [] }
        return source == "custom" || source.hasPrefix("library:") ? .connected : []
    }
}
