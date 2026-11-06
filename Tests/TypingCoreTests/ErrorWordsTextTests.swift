import Foundation
import Testing
@testable import TypingCore

struct ErrorWordsTextTests {
    func entry(_ s: String, errors: Int = 1, at: Double = 0) -> ErrorWordEntry {
        ErrorWordEntry(text: s, isPhrase: s.contains(" "), errors: errors, cleanStreak: 0,
                       firstSeen: Date(timeIntervalSince1970: at), lastSeen: Date(timeIntervalSince1970: at))
    }
    var many: [ErrorWordEntry] {
        ["мыла", "раму", "дом", "кошка", "собака", "лодка", "ветер", "река", "поле", "лес", "гора", "сосна"]
            .enumerated().map { entry($1, errors: $0 + 1, at: Double($0)) }
    }

    @Test func tooFewReturnsNil() {
        #expect(ErrorWordsText.make(entries: Array(many.prefix(4)), allowed: nil, targetChars: 200, seed: 1) == nil)
    }

    @Test func allowedFiltersWords() {
        let allowed = Set("мылараудомкшсб")
        // Из 12 слов только часть из этих букв; убедимся, что чужие не попадают.
        let text = ErrorWordsText.make(entries: many, allowed: allowed, targetChars: 200, seed: 3) ?? ""
        for w in text.split(separator: " ") { #expect(w.allSatisfy { allowed.contains($0) }) }
        let few = ErrorWordsText.make(entries: many, allowed: Set("мыла"), targetChars: 200, seed: 3)
        #expect(few == nil)
    }

    @Test func lengthAndRepeats() throws {
        let text = try #require(ErrorWordsText.make(entries: many, allowed: nil, targetChars: 200, seed: 7))
        #expect(text.count >= 150 && text.count <= 230)
        var counts: [Substring: Int] = [:]
        for w in text.split(separator: " ") { counts[w, default: 0] += 1 }
        for (_, c) in counts { #expect((2...3).contains(c)) }
    }

    @Test func deterministic() {
        let a = ErrorWordsText.make(entries: many, allowed: nil, targetChars: 200, seed: 42)
        let b = ErrorWordsText.make(entries: many, allowed: nil, targetChars: 200, seed: 42)
        #expect(a == b)
    }
}

extension ErrorWordsTextTests {
    @Test func apostropheIsNotALetterForFilter() {
        let entries = [entry("you're"), entry("didn't")]
        let allowed = Set("youredidnt")
        #expect(ErrorWordsText.eligible(entries: entries, allowed: allowed).count == 2)
        #expect(ErrorWordsText.eligible(entries: entries, allowed: Set("youre")).count == 1)
    }
}
