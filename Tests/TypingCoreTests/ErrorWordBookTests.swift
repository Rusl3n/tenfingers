import Foundation
import Testing
@testable import TypingCore

struct ErrorWordBookTests {
    let t0 = Date(timeIntervalSince1970: 1000)
    func bad(_ s: String) -> WordHit { WordHit(text: s, isPhrase: false, hadError: true) }
    func ok(_ s: String) -> WordHit { WordHit(text: s, isPhrase: false, hadError: false) }

    @Test func newErrorCreatesEntry() {
        let r = ErrorWordBook.apply([bad("Мыла")], to: [], now: t0)
        #expect(r.entries.count == 1)
        #expect(r.entries[0].text == "мыла")
        #expect(r.entries[0].errors == 1)
        #expect(r.entries[0].firstSeen == t0)
        #expect(r.fixed == 0)
    }

    @Test func threeCleanRunsFixWord() {
        var list = ErrorWordBook.apply([bad("мыла")], to: [], now: t0).entries
        var fixed = 0
        for _ in 0..<3 {
            let r = ErrorWordBook.apply([ok("мыла")], to: list, now: t0)
            list = r.entries; fixed += r.fixed
        }
        #expect(list.isEmpty)
        #expect(fixed == 1)
    }

    @Test func errorResetsStreak() {
        var list = ErrorWordBook.apply([bad("мыла")], to: [], now: t0).entries
        for _ in 0..<2 { list = ErrorWordBook.apply([ok("мыла")], to: list, now: t0).entries }
        #expect(list[0].cleanStreak == 2)
        let later = t0.addingTimeInterval(10)
        list = ErrorWordBook.apply([bad("мыла")], to: list, now: later).entries
        #expect(list[0].cleanStreak == 0)
        #expect(list[0].errors == 2)
        #expect(list[0].lastSeen == later)
    }

    @Test func cleanUnknownWordAddsNothing() {
        let r = ErrorWordBook.apply([ok("дом")], to: [], now: t0)
        #expect(r.entries.isEmpty)
    }

    @Test func overflowEvictsOldest() {
        var list: [ErrorWordEntry] = []
        for i in 0..<ErrorWordBook.limit {
            list.append(ErrorWordEntry(text: "слово\(i)", isPhrase: false, errors: 1, cleanStreak: 0,
                                       firstSeen: t0.addingTimeInterval(Double(i + 1)),
                                       lastSeen: t0.addingTimeInterval(Double(i + 1))))
        }
        let r = ErrorWordBook.apply([bad("новое")], to: list, now: t0.addingTimeInterval(9999))
        #expect(r.entries.count == ErrorWordBook.limit)
        #expect(!r.entries.contains { $0.text == "слово0" })
        #expect(r.entries.contains { $0.text == "новое" })
    }

    @Test func phraseIsFixedByThreeCleanPairsWithoutCountingFixed() {
        let badPhrase = WordHit(text: "мыла раму", isPhrase: true, hadError: true)
        let okPhrase = WordHit(text: "мыла раму", isPhrase: true, hadError: false)
        var list = ErrorWordBook.apply([badPhrase], to: [], now: t0).entries
        var fixed = 0
        for _ in 0..<3 {
            let r = ErrorWordBook.apply([okPhrase], to: list, now: t0)
            list = r.entries; fixed += r.fixed
        }
        #expect(list.isEmpty)
        #expect(fixed == 0)
    }

    @Test func cleanHitForUnknownPhraseDoesNothing() {
        let r = ErrorWordBook.apply([WordHit(text: "мыла раму", isPhrase: true, hadError: false)], to: [], now: t0)
        #expect(r.entries.isEmpty)
    }

    @Test func everyOccurrenceCountsInOrder() {
        var entry = ErrorWordEntry(text: "мыла", isPhrase: false, errors: 1, cleanStreak: 0, firstSeen: t0, lastSeen: t0)
        let three = ErrorWordBook.apply([ok("мыла"), ok("мыла"), ok("мыла")], to: [entry], now: t0)
        #expect(three.entries.isEmpty)
        #expect(three.fixed == 1)
        entry.cleanStreak = 0
        let mixed = ErrorWordBook.apply([ok("мыла"), bad("мыла"), ok("мыла")], to: [entry], now: t0)
        #expect(mixed.entries.count == 1)
        #expect(mixed.entries[0].cleanStreak == 1)
        #expect(mixed.entries[0].errors == 2)
        #expect(mixed.fixed == 0)
    }

    @Test func newErrorThenThreeCleanInOneTextIsFixed() {
        let r = ErrorWordBook.apply([bad("мыла"), ok("мыла"), ok("мыла"), ok("мыла")], to: [], now: t0)
        #expect(r.entries.isEmpty)
        #expect(r.fixed == 1)
    }

    @Test func cleanOccurrencesAfterRemovalDoNothing() {
        let entry = ErrorWordEntry(text: "мыла", isPhrase: false, errors: 1, cleanStreak: 2, firstSeen: t0, lastSeen: t0)
        let r = ErrorWordBook.apply([ok("мыла"), ok("мыла"), ok("мыла")], to: [entry], now: t0)
        #expect(r.entries.isEmpty)
        #expect(r.fixed == 1)
    }

    @Test func evictionSparesEntriesTouchedByThisCall() {
        // Кривые часы: now раньше всех lastSeen. Затронутая запись не должна вытесняться.
        let old = Date(timeIntervalSince1970: 5000)
        var list = (0..<ErrorWordBook.limit).map {
            ErrorWordEntry(text: "слово\($0)", isPhrase: false, errors: 1, cleanStreak: 0, firstSeen: old, lastSeen: old)
        }
        list[0].lastSeen = old.addingTimeInterval(1)
        let r = ErrorWordBook.apply([bad("новое")], to: list, now: t0)
        #expect(r.entries.count == ErrorWordBook.limit)
        #expect(r.entries.contains { $0.text == "новое" })
    }
}
