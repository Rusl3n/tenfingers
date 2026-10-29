import Foundation
import Testing
@testable import TypingCore

// Корпус предложений Tatoeba (§2.5, решение 21).

@Test func corpusSentencesDecode() throws {
    let json = """
    [
    {"text": "Я люблю читать.", "traits": 3, "source": "tatoeba:1234"},
    {"text": "у нас 2 кота", "traits": 4, "source": "tatoeba:98765"}
    ]
    """
    let sentences = try JSONDecoder().decode([CorpusSentence].self, from: Data(json.utf8))
    #expect(sentences == [
        CorpusSentence(text: "Я люблю читать.", traits: 3, source: "tatoeba:1234"),
        CorpusSentence(text: "у нас 2 кота", traits: 4, source: "tatoeba:98765"),
    ])
    #expect(TextTraits(rawValue: sentences[0].traits) == TextTraits.of(sentences[0].text))
}

@Test func corpusLoadDoesNotFailWithoutResource() throws {
    // До шага C файла может не быть: тогда пустой массив.
    for language in Language.allCases {
        let sentences = try SentenceCorpus.load(language)
        #expect(sentences.count >= 0)
        #expect(sentences.allSatisfy { $0.source.hasPrefix("tatoeba:") })
    }
}
