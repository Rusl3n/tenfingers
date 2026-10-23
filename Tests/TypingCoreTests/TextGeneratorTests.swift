import Testing
@testable import TypingCore

private let generator = TextGenerator(wordList: WordList(words: [
    "вал", "лава", "дал", "два", "вода", "дыра", "пар", "парад", "двор", "ода", "жало", "фара",
]))

private func onlyAllowed(_ text: String, _ allowed: Set<Character>) -> Bool {
    text.allSatisfy { $0 == " " || allowed.contains($0) }
}

@Test func seededGeneratorIsDeterministic() {
    var a = SeededGenerator(seed: 42)
    var b = SeededGenerator(seed: 42)
    #expect((0..<5).map { _ in a.next() } == (0..<5).map { _ in b.next() })
}

@Test func drillUsesOnlyNewKeys() {
    var rng = SeededGenerator(seed: 1)
    let text = generator.drill(keys: ["а", "о"], length: 80, rng: &rng)
    #expect(text.count >= 80)
    #expect(onlyAllowed(text, ["а", "о"]))
    #expect(text.hasPrefix("аааа оооо аоао"))
}

@Test func combosAlwaysContainNewKey() {
    var rng = SeededGenerator(seed: 2)
    let allowed: Set<Character> = ["а", "о", "в", "л", " "]
    let text = generator.combos(newKeys: ["в", "л"], allowed: allowed, length: 100, rng: &rng)
    #expect(onlyAllowed(text, allowed))
    for token in text.split(separator: " ") {
        #expect(token.contains("в") || token.contains("л"), "\(token)")
    }
}

@Test func wordsUseOnlyAllowedLetters() {
    var rng = SeededGenerator(seed: 3)
    let allowed: Set<Character> = Set("авлдыр ")
    let text = generator.words(allowed: allowed, focus: ["ы"], length: 120, capitalRate: 0, rng: &rng)
    #expect(text.count >= 120)
    #expect(onlyAllowed(text, allowed))
    #expect(text.contains("ы"))
}

@Test func wordsWithCapitalsUseUppercaseOfAllowedLetters() {
    var rng = SeededGenerator(seed: 4)
    let allowed: Set<Character> = Set("авлдо ")
    let text = generator.words(allowed: allowed, focus: [], length: 200, capitalRate: 0.5, rng: &rng)
    let withUpper = allowed.union(Set("АВЛДО"))
    #expect(onlyAllowed(text, withUpper))
    #expect(text.contains { $0.isUppercase })
}

@Test func symbolsAreAttachedAndRespectPairs() {
    var rng = SeededGenerator(seed: 5)
    let allowed: Set<Character> = Set("авлдо ()1234%")
    let text = generator.words(allowed: allowed, focus: ["(", ")", "%"], length: 300, capitalRate: 0, rng: &rng)
    #expect(onlyAllowed(text, allowed))
    #expect(text.contains("("))
    #expect(text.filter { $0 == "(" }.count == text.filter { $0 == ")" }.count)
    #expect(text.contains("%"))
}

@Test func unpairedBracketIsUsedAsSuffix() {
    var rng = SeededGenerator(seed: 6)
    let allowed: Set<Character> = Set("авл [")
    let text = generator.words(allowed: allowed, focus: ["["], length: 100, capitalRate: 0, rng: &rng)
    #expect(onlyAllowed(text, allowed))
    #expect(text.contains("["))
}

@Test func digitsBecomeNumbers() {
    var rng = SeededGenerator(seed: 7)
    let allowed: Set<Character> = Set("авл 12345")
    let text = generator.words(allowed: allowed, focus: Set("12345"), length: 150, capitalRate: 0, rng: &rng)
    #expect(onlyAllowed(text, allowed))
    #expect(text.contains { $0.isNumber })
}

@Test func pseudoWordUsesOnlyGivenLettersAndFocus() {
    var rng = SeededGenerator(seed: 8)
    for _ in 0..<50 {
        let word = generator.pseudoWord(letters: ["а", "о"], focus: ["о"], rng: &rng)
        #expect(word.count >= 2 && word.count <= 7)
        #expect(word.allSatisfy { $0 == "а" || $0 == "о" })
        #expect(word.contains("о"))
    }
}

@Test func sameSeedGivesSameText() {
    var a = SeededGenerator(seed: 9)
    var b = SeededGenerator(seed: 9)
    let allowed: Set<Character> = Set("авлдыро ")
    #expect(generator.words(allowed: allowed, focus: [], length: 100, capitalRate: 0, rng: &a)
            == generator.words(allowed: allowed, focus: [], length: 100, capitalRate: 0, rng: &b))
}

@Test func neverCapitalizesYo() {
    // Shift+ё в RussianWin даёт U+00CB, поэтому заглавная Ё не должна появляться.
    let yoGenerator = TextGenerator(wordList: WordList(words: ["ёлка", "ёж", "ёлки", "ёжик", "лёд", "лес"]))
    let allowed: Set<Character> = Set("ёлкажиес ")
    for seed in 1...20 {
        var rng = SeededGenerator(seed: UInt64(seed))
        let text = yoGenerator.words(allowed: allowed, focus: ["ё"], length: 200, capitalRate: 1.0, rng: &rng)
        #expect(text.contains("ё"))
        #expect(!text.contains("Ё"), "seed \(seed)")
    }
}
