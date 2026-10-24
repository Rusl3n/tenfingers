import Testing
@testable import TypingCore

private let trainer = AdaptiveTrainer(language: .ru, targetCpm: 175)
private func mastered() -> KeyMastery { KeyMastery(ewmaMs: 300, errorRate: 0.02, presses: 40) }

@Test func adaptiveOrderCoversAlphabet() {
    for language in Language.allCases {
        #expect(Set(language.adaptiveOrder) == language.letters)
        #expect(language.adaptiveOrder.count == language.letters.count)
    }
    #expect(Array(Language.ru.adaptiveOrder.prefix(6)) == Array("оеаинт"))
}

@Test func startsWithSixLetters() {
    #expect(trainer.unlockedLetters(count: 0) == Array("оеаинт"))
    #expect(trainer.unlockedLetters(count: 8) == Array("оеаинтср"))
}

@Test func masteryNeedsSpeedAccuracyAndVolume() {
    #expect(trainer.thresholdMs.rounded() == 343)
    #expect(trainer.isMastered(mastered()))
    #expect(!trainer.isMastered(KeyMastery(ewmaMs: 400, errorRate: 0, presses: 40)))
    #expect(!trainer.isMastered(KeyMastery(ewmaMs: 300, errorRate: 0.1, presses: 40)))
    #expect(!trainer.isMastered(KeyMastery(ewmaMs: 300, errorRate: 0, presses: 10)))
    #expect(!trainer.isMastered(nil))
}

@Test func unlocksNextWhenAllMastered() {
    var stats: [Character: KeyMastery] = [:]
    for c in "оеаинт" { stats[c] = mastered() }
    #expect(trainer.nextUnlockedCount(current: 6, stats: stats) == 7)
    stats["т"] = KeyMastery(ewmaMs: 500, errorRate: 0, presses: 40)
    #expect(trainer.nextUnlockedCount(current: 6, stats: stats) == 6)
}

@Test func focusIsWeakestUnlockedLetter() {
    var stats: [Character: KeyMastery] = [:]
    for c in "оеаинт" { stats[c] = mastered() }
    stats["и"] = KeyMastery(ewmaMs: 600, errorRate: 0.02, presses: 40)
    #expect(trainer.focusLetter(unlocked: Array("оеаинт"), stats: stats) == "и")
    stats["и"] = mastered()
    stats["н"] = nil
    #expect(trainer.focusLetter(unlocked: Array("оеаинт"), stats: stats) == "н")
}

@Test func focusPrefersUnmasteredLetterWithTooFewPresses() {
    var stats: [Character: KeyMastery] = [:]
    for c in "оеаинт" { stats[c] = mastered() }
    // Быстрая, но ещё не набравшая объём буква против освоенной «на грани».
    stats["т"] = KeyMastery(ewmaMs: 300, errorRate: 0, presses: 24)
    stats["и"] = KeyMastery(ewmaMs: 340, errorRate: 0.04, presses: 60)
    #expect(trainer.isMastered(stats["и"]))
    #expect(!trainer.isMastered(stats["т"]))
    #expect(trainer.focusLetter(unlocked: Array("оеаинт"), stats: stats) == "т")
}

@Test func focusFallsBackToPureWeaknessWhenAllMastered() {
    var stats: [Character: KeyMastery] = [:]
    for c in "оеаинт" { stats[c] = mastered() }
    stats["и"] = KeyMastery(ewmaMs: 340, errorRate: 0.04, presses: 60)
    #expect(trainer.focusLetter(unlocked: Array("оеаинт"), stats: stats) == "и")
}

@Test func masteryProgressIsBetweenZeroAndOne() {
    #expect(trainer.masteryProgress(nil) == 0)
    #expect(trainer.masteryProgress(mastered()) == 1)
    let half = trainer.masteryProgress(KeyMastery(ewmaMs: 686, errorRate: 0, presses: 40))
    #expect(half > 0.45 && half < 0.55)
}

@Test func exerciseUsesOnlyUnlockedLettersAndFocus() {
    let generator = TextGenerator(wordList: try! WordList.load(.ru))
    var rng = SeededGenerator(seed: 3)
    let text = trainer.exercise(generator: generator, unlocked: Array("оеаинт"), focus: "и", rng: &rng)
    // fill считает и разделители, поэтому длина может быть чуть меньше порции.
    #expect(text.count >= 230)
    #expect(text.allSatisfy { $0 == " " || "оеаинт".contains($0) })
    #expect(text.contains("и"))
}
