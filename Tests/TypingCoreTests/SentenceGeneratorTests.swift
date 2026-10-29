import Testing
@testable import TypingCore

// Генератор предложений из открытых слов (§2.5, п. 4).

private let textGenerator = TextGenerator(wordList: WordList(words: [
    "вал", "лава", "дал", "два", "вода", "дыра", "пар", "парад", "двор", "ода", "жало", "фара",
]))
private let sentences = SentenceGenerator(generator: textGenerator)
private let letters: Set<Character> = Set("авлдорпыжф")
private let pool = textGenerator.pool(letters: letters, kind: .all)

@Test func sentenceWithoutCapitalsAndPeriodIsPlainWords() {
    let allowed = letters.union([" "])
    for seed in 1...10 {
        var rng = SeededGenerator(seed: UInt64(seed))
        let text = sentences.sentence(language: .ru, allowed: allowed, capitals: false, digits: false, focus: [],
                                      pool: pool, rng: &rng)
        #expect(!text.contains { $0.isUppercase } && !text.contains("."), "\(text)")
        #expect((4...9).contains(text.split(separator: " ").count), "\(text)")
        #expect(text.allSatisfy(allowed.contains))
    }
}

@Test func sentenceStartsWithCapitalAndEndsWithPeriod() {
    let allowed = letters.union([" ", "."])
    for seed in 1...10 {
        var rng = SeededGenerator(seed: UInt64(seed))
        let text = sentences.sentence(language: .ru, allowed: allowed, capitals: true, digits: false, focus: [],
                                      pool: pool, rng: &rng)
        #expect(text.first!.isUppercase, "\(text)")
        #expect(text.last == ".", "\(text)")
        #expect(text.dropFirst().filter(\.isUppercase).isEmpty, "\(text)")
    }
}

@Test func sentenceUsesCommaWhenOpen() {
    let allowed = letters.union([" ", ".", ","])
    var withComma = 0
    for seed in 1...50 {
        var rng = SeededGenerator(seed: UInt64(seed))
        let text = sentences.sentence(language: .ru, allowed: allowed, capitals: true, digits: false, focus: [],
                                      pool: pool, rng: &rng)
        if text.contains(",") { withComma += 1 }
        #expect(!text.contains(",.") && !text.hasPrefix(","), "\(text)")
    }
    #expect(withComma > 0)
}

@Test func sentenceUsesDigitTokensWhenDigitsAreOpen() {
    let allowed = letters.union(Set(" .,0123456789"))
    var withDigit = 0
    for seed in 1...50 {
        var rng = SeededGenerator(seed: UInt64(seed))
        let text = sentences.sentence(language: .ru, allowed: allowed, capitals: true, digits: true, focus: [],
                                      pool: pool, rng: &rng)
        if text.contains(where: \.isNumber) { withDigit += 1 }
        #expect(text.allSatisfy { allowed.contains($0) || allowed.contains(Character($0.lowercased())) }, "\(text)")
    }
    #expect(withDigit > 0)
    var rng = SeededGenerator(seed: 1)
    let noDigits = sentences.text(language: .ru, allowed: allowed, capitals: true, digits: false, focus: [],
                                  pool: pool, length: 300, rng: &rng)
    #expect(!noDigits.contains { $0.isNumber })
}

@Test func sentenceFavoursFocusLetters() {
    var rng = SeededGenerator(seed: 4)
    let text = sentences.text(language: .ru, allowed: letters.union([" "]), capitals: false, digits: false,
                              focus: ["ж"], pool: pool, length: 600, rng: &rng)
    let words = text.split(separator: " ")
    #expect(Double(words.filter { $0.contains("ж") }.count) / Double(words.count) > 0.4)
}

@Test func sentenceTextReachesLength() {
    var rng = SeededGenerator(seed: 7)
    let text = sentences.text(language: .ru, allowed: letters.union([" ", "."]), capitals: true, digits: false,
                              focus: [], pool: pool, length: 200, rng: &rng)
    #expect(text.count >= 200)
    #expect(!text.contains("  ") && !text.hasSuffix(" "))
}
