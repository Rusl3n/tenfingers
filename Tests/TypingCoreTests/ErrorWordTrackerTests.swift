import Testing
@testable import TypingCore

struct ErrorWordTrackerTests {
    let vocabulary: Set<String> = ["мама", "мыла", "раму", "кто-то", "да", "дом", "белый", "you", "dogs", "tis", "don't"]

    // "Мама мыла раму." — «ы» в «мыла» на индексе 6.
    @Test func singleErrorWord() {
        let hits = ErrorWordTracker.hits(text: "Мама мыла раму.", errorPositions: [6], vocabulary: vocabulary)
        #expect(hits == [
            WordHit(text: "мама", isPhrase: false, hadError: false),
            WordHit(text: "мыла", isPhrase: false, hadError: true),
            WordHit(text: "раму", isPhrase: false, hadError: false)
        ])
    }

    @Test func adjacentErrorWordsGiveNoPhrase() {
        let hits = ErrorWordTracker.hits(text: "Мама мыла раму.", errorPositions: [6, 10], vocabulary: vocabulary)
        #expect(hits.allSatisfy { !$0.isPhrase })
        #expect(hits.map(\.text) == ["мама", "мыла", "раму"])
        #expect(hits.map(\.hadError) == [false, true, true])
    }

    @Test func shortWordsAreDropped() {
        let hits = ErrorWordTracker.hits(text: "мама и раму", errorPositions: [0, 5, 7], vocabulary: vocabulary + ["и"])
        #expect(!hits.contains { $0.text == "и" })
    }

    @Test func hyphenInsideKeptEdgesTrimmed() {
        let hits = ErrorWordTracker.hits(text: "кто-то -да-", errorPositions: [], vocabulary: vocabulary)
        #expect(hits.map(\.text) == ["кто-то", "да"])
    }

    @Test func everyOccurrenceGivesItsOwnHitInTextOrder() {
        let hits = ErrorWordTracker.hits(text: "дом дом дом", errorPositions: [5], vocabulary: vocabulary)
        #expect(hits.map(\.text) == ["дом", "дом", "дом"])
        #expect(hits.map(\.hadError) == [false, true, false])
    }

    @Test func wordsOutsideVocabularyAreNotTracked() {
        let hits = ErrorWordTracker.hits(text: "дсэо бт тсп мама", errorPositions: [0, 5], vocabulary: vocabulary)
        #expect(hits == [WordHit(text: "мама", isPhrase: false, hadError: false)])
    }

    @Test func hyphenatedWordAcceptedByParts() {
        let hits = ErrorWordTracker.hits(text: "дом-мама дом-бт", errorPositions: [], vocabulary: vocabulary)
        #expect(hits.map(\.text) == ["дом-мама"])
    }

    @Test func hyphenPartsShorterThanTwoLettersAreRejected() {
        #expect(!ErrorWordFilter.isAllowed(text: "дом-я", isPhrase: false, vocabulary: vocabulary + ["я"]))
    }

    @Test func phrasesAreNeverAllowed() {
        #expect(!ErrorWordFilter.isAllowed(text: "мама мыла", isPhrase: true, vocabulary: vocabulary))
        #expect(!ErrorWordFilter.isAllowed(text: "мама мыла", isPhrase: false, vocabulary: vocabulary))
        #expect(ErrorWordFilter.isAllowed(text: "мама", isPhrase: false, vocabulary: vocabulary))
        #expect(!ErrorWordFilter.isAllowed(text: "бт", isPhrase: false, vocabulary: vocabulary))
    }

    @Test func apostropheInsideWordIsKeptWhenInVocabulary() {
        let hits = ErrorWordTracker.hits(text: "don't you're", errorPositions: [1], vocabulary: vocabulary)
        #expect(hits == [WordHit(text: "don't", isPhrase: false, hadError: true)])
    }

    @Test func edgeApostrophesAreTrimmed() {
        let hits = ErrorWordTracker.hits(text: "'tis dogs' ", errorPositions: [], vocabulary: vocabulary)
        #expect(hits.map(\.text) == ["tis", "dogs"])
    }
}

private func + (lhs: Set<String>, rhs: Set<String>) -> Set<String> { lhs.union(rhs) }
