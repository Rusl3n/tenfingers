import Testing
@testable import TypingCore

@Test func worstKeysRankByWeaknessAndNeedVolume() {
    let stats: [Character: KeyMastery] = [
        "а": KeyMastery(ewmaMs: 300, errorRate: 0, presses: 50),
        "б": KeyMastery(ewmaMs: 700, errorRate: 0.2, presses: 50),
        "в": KeyMastery(ewmaMs: 500, errorRate: 0, presses: 50),
        "г": KeyMastery(ewmaMs: 900, errorRate: 0.5, presses: 3),
    ]
    #expect(WeakSpots.worstKeys(stats, thresholdMs: 343, limit: 2) == ["б", "в"])
}

@Test func worstBigramsNeedFiveOccurrences() {
    let stats: [String: KeyMastery] = [
        "ыв": KeyMastery(ewmaMs: 800, errorRate: 0.3, presses: 6),
        "ао": KeyMastery(ewmaMs: 300, errorRate: 0, presses: 30),
        "щу": KeyMastery(ewmaMs: 990, errorRate: 0.9, presses: 2),
    ]
    #expect(WeakSpots.worstBigrams(stats, thresholdMs: 343, limit: 5) == ["ыв", "ао"])
}

@Test func focusedWordsContainFocus() {
    let generator = TextGenerator(wordList: try! WordList.load(.ru))
    var rng = SeededGenerator(seed: 5)
    let text = generator.focusedWords(letters: Language.ru.letters, focusKeys: ["щ"], focusBigrams: ["ыв"],
                                      length: 300, rng: &rng)
    let words = text.split(separator: " ")
    let hits = words.filter { $0.contains("щ") || $0.contains("ыв") }.count
    #expect(Double(hits) / Double(words.count) > 0.6)
    #expect(text.allSatisfy { $0 == " " || Language.ru.letters.contains($0) })
}

@Test func focusedWordsKeepRareKeyAmongCommonOnes() {
    let generator = TextGenerator(wordList: try! WordList.load(.ru))
    var rng = SeededGenerator(seed: 9)
    let text = generator.focusedWords(letters: Language.ru.letters, focusKeys: ["в", "ъ"], focusBigrams: [],
                                      length: 600, rng: &rng)
    let words = text.split(separator: " ")
    let rare = words.filter { $0.contains("ъ") }.count
    #expect(Double(rare) / Double(words.count) >= 0.2)
}

private let smallGenerator = TextGenerator(wordList: WordList(words: [
    "вал", "лава", "дал", "два", "вода", "дыра", "пар", "парад", "двор", "ода", "жало", "фара",
]))

@Test func focusedWordsFallBackWhenNoWordMatches() {
    var rng = SeededGenerator(seed: 3)
    let letters: Set<Character> = Set("авлдорпыжфъ")
    // «ъ» нет ни в одном слове: цель заменяется псевдословом с этой буквой, а при его отсутствии — обычным словом.
    let text = smallGenerator.focusedWords(letters: letters, focusKeys: ["ъ"], focusBigrams: ["ъъ"],
                                           length: 200, rng: &rng)
    #expect(text.count >= 200)
    #expect(text.allSatisfy { $0 == " " || letters.contains($0) })
    #expect(text.contains("ъ"))
}

@Test func focusedWordsAreEmptyWhenNoWordFitsLetters() {
    var rng = SeededGenerator(seed: 4)
    #expect(smallGenerator.focusedWords(letters: ["щ", "ш"], focusKeys: ["щ"], focusBigrams: [],
                                        length: 100, rng: &rng).isEmpty)
    #expect(smallGenerator.focusedWords(letters: [], focusKeys: [], focusBigrams: [], length: 100, rng: &rng).isEmpty)
}

@Test func focusedWordsWorkWithBigramOnlyFocus() {
    var rng = SeededGenerator(seed: 6)
    let letters: Set<Character> = Set("авлдорпыжфъ")
    let text = smallGenerator.focusedWords(letters: letters, focusKeys: [], focusBigrams: ["ар"],
                                           length: 400, rng: &rng)
    let words = text.split(separator: " ")
    let hits = words.filter { $0.contains("ар") }.count
    #expect(Double(hits) / Double(words.count) > 0.6)
}

@Test func focusedWordsDeduplicateTargets() {
    // «ъ» повторён десять раз, «в» один: после слияния «в» получает не меньше доли, чем «ъ».
    var rng = SeededGenerator(seed: 11)
    let letters: Set<Character> = Set("авлдорпыжфъ")
    let text = smallGenerator.focusedWords(letters: letters, focusKeys: Array(repeating: "ж", count: 10) + ["в"],
                                           focusBigrams: ["ар", "ар", "ар"], length: 2000, rng: &rng)
    let words = text.split(separator: " ")
    let withV = words.filter { $0.contains("в") }.count
    let withZh = words.filter { $0.contains("ж") }.count
    #expect(withZh > 0)
    #expect(Double(withV) > Double(withZh) * 0.8)
}

// MARK: - «Повтор» и «Ускорение» (§6.1–§6.2)

@Test func mostErrorsRankByErrorShareThenVolume() {
    let keys: [Character: KeyMastery] = [
        "а": KeyMastery(ewmaMs: 300, errorRate: 0.2, presses: 20),
        "б": KeyMastery(ewmaMs: 300, errorRate: 0.2, presses: 40),   // та же доля, больше нажатий — выше
        "в": KeyMastery(ewmaMs: 300, errorRate: 0.5, presses: 9),    // мало нажатий
        "г": KeyMastery(ewmaMs: 900, errorRate: 0, presses: 50),     // без ошибок
        "д": KeyMastery(ewmaMs: 300, errorRate: 0.1, presses: 30),
        "ъ": KeyMastery(ewmaMs: 300, errorRate: 0.9, presses: 30),   // не открыта
    ]
    let bigrams: [String: KeyMastery] = [
        "ъе": KeyMastery(ewmaMs: 300, errorRate: 0.9, presses: 10),  // «ъ» не открыта
        "ад": KeyMastery(ewmaMs: 300, errorRate: 0.3, presses: 5),
        "ба": KeyMastery(ewmaMs: 300, errorRate: 0.4, presses: 4),   // мало появлений
        "да": KeyMastery(ewmaMs: 300, errorRate: 0, presses: 40),
    ]
    let result = WeakSpots.mostErrors(keys: keys, bigrams: bigrams, allowed: Set("абвгдеё"))
    #expect(result.keys == ["б", "а", "д"])
    #expect(result.bigrams == ["ад"])
    #expect(WeakSpots.mostErrors(keys: keys, bigrams: bigrams, allowed: Set("абвгдеё"), limit: 1).keys == ["б"])
}

@Test func mostErrorsBreaksFullTiesAlphabetically() {
    let same = KeyMastery(ewmaMs: 300, errorRate: 0.2, presses: 20)
    let result = WeakSpots.mostErrors(keys: ["в": same, "а": same, "б": same], bigrams: [:], allowed: Set("абв"))
    #expect(result.keys == ["а", "б", "в"])
}

@Test func strongKeysNeedLowErrorsAndVolume() {
    let strong = KeyMastery(ewmaMs: 300, errorRate: 0.02, presses: 30)
    let allowed: Set<Character> = Set("абвгдежз .,АБЖ")  // заглавные в «открытые буквы» не входят
    var keys: [Character: KeyMastery] = [
        "е": strong, "д": strong, "г": strong, "в": strong, "б": strong, "а": strong,
        "ж": KeyMastery(ewmaMs: 300, errorRate: 0.03, presses: 100),
        "з": KeyMastery(ewmaMs: 300, errorRate: 0, presses: 29),
    ]
    #expect(WeakSpots.strongKeys(keys, allowed: allowed) == ["а", "б", "в", "г", "д", "е"])
    keys["е"] = nil
    #expect(WeakSpots.strongKeys(keys, allowed: allowed) == ["а", "б", "в", "г", "д", "е", "ж", "з"])
}
