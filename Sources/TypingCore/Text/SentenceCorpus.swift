import Foundation

/// Предложение корпуса (`sentences-<lang>.json`, Tatoeba, CC BY 2.0 FR; §2.5, решение 21).
public struct CorpusSentence: Codable, Equatable, Sendable {
    public let text: String
    /// Битовая маска как у `TextTraits`: 1 — заглавные, 2 — знаки, 4 — цифры.
    public let traits: Int
    /// `tatoeba:<id>`.
    public let source: String

    public init(text: String, traits: Int, source: String) {
        self.text = text
        self.traits = traits
        self.source = source
    }
}

/// Встроенный корпус предложений для шагов `sentences` и `text` (§2.5).
public enum SentenceCorpus {
    /// `sentences-<lang>.json`; файла нет (до шага C) — пустой массив.
    public static func load(_ language: Language) throws -> [CorpusSentence] {
        guard let url = CoreResources.bundle.url(forResource: "sentences-\(language.rawValue)", withExtension: "json")
        else { return [] }
        return try JSONDecoder().decode([CorpusSentence].self, from: Data(contentsOf: url))
    }
}
