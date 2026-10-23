import Foundation

/// Частотный словарь: слова в нижнем регистре, от частых к редким.
public struct WordList: Sendable {
    public let words: [String]

    public init(words: [String]) {
        self.words = words
    }

    public static func load(_ language: Language) throws -> WordList {
        let url = try CoreResources.url("words-\(language.rawValue)", "txt")
        let text = try String(contentsOf: url, encoding: .utf8)
        return WordList(words: text.split(whereSeparator: \.isNewline).map(String.init))
    }

    /// Слова, составленные только из разрешённых букв (порядок частоты сохраняется).
    public func words(using allowed: Set<Character>) -> [String] {
        words.filter { $0.allSatisfy(allowed.contains) }
    }
}
