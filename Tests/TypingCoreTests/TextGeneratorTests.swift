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

// MARK: - Генераторы издания 2 (§2.2, §2.4)

private let rowGenerator = TextGenerator(wordList: WordList(words: ["кен", "гена", "аква", "вол", "кол", "нога"]))

@Test func rowWordsWithFullShareUseOnlyRowLetters() {
    let row: Set<Character> = ["к", "е", "н", "г"]
    var rng = SeededGenerator(seed: 1)
    let text = rowGenerator.rowWords(rowLetters: row, allowed: Set("кенгавлоы "), minShare: 1, length: 100, rng: &rng)
    #expect(text.count >= 100)
    // Только «кен» из словаря или псевдослова из букв ряда.
    for token in text.split(separator: " ") { #expect(token.allSatisfy(row.contains), "\(token)") }
    #expect(text.split(separator: " ").contains("кен"))
}

@Test func rowWordsLowerTheShareWhenWordsAreFew() {
    // Порог 0,6 → 0,5: «нога» (н, г из ряда — половина букв) проходит, «аква» (четверть) — нет.
    let row: Set<Character> = ["к", "е", "н", "г"]
    var seen: Set<Substring> = []
    for seed in 1...5 {
        var rng = SeededGenerator(seed: UInt64(seed))
        let text = rowGenerator.rowWords(rowLetters: row, allowed: Set("кенгавлоы "), minShare: 0.6, length: 200,
                                         rng: &rng)
        seen.formUnion(text.split(separator: " "))
    }
    #expect(seen.contains("нога") && seen.contains("гена"))
    #expect(!seen.contains("аква") && !seen.contains("вол") && !seen.contains("кол"))
}

@Test func rowWordsForPairsMixBothRows() {
    let top: Set<Character> = ["к", "е", "н", "г"]
    let home: Set<Character> = ["а", "в", "о", "л", "ы"]
    let pairGenerator = TextGenerator(wordList: WordList(words: [
        "кен", "гена", "аква", "вол", "кол", "нога", "око", "лава", "вола", "овал", "алла", "ваал",
    ]))
    for seed in 1...20 {
        var rng = SeededGenerator(seed: UInt64(seed))
        let text = pairGenerator.rowWords(rowLetters: top.union(home), allowed: top.union(home).union([" "]),
                                          minShare: 0.6, length: 200, pairs: (top, home), rng: &rng)
        let tokens = text.split(separator: " ")
        let both = tokens.filter { $0.contains(where: top.contains) && $0.contains(where: home.contains) }
        #expect(Double(both.count) / Double(tokens.count) >= 0.4, "seed \(seed): \(text)")
        #expect(text.count >= 200)
    }
}

@Test func phrasesUseOnlyAllowedLowercaseLetters() {
    let allowed: Set<Character> = Set("авлдорпыжф ")
    for seed in 1...5 {
        var rng = SeededGenerator(seed: UInt64(seed))
        let text = generator.phrases(allowed: allowed, focus: ["ж"], length: 150, rng: &rng)
        #expect(text.count >= 150)
        #expect(text.count <= 150 + 20, "перебор длины — не больше одного слова")
        #expect(onlyAllowed(text, allowed))
        #expect(!text.contains { $0.isUppercase || $0.isPunctuation })
        #expect(text.contains("ж"))
    }
}

@Test func errorWordsComeInPairsWithTargets() {
    let letters: Set<Character> = Set("авлдорыпжф")
    for seed in 1...5 {
        var rng = SeededGenerator(seed: UInt64(seed))
        let text = generator.errorWords(letters: letters, targets: ["р", "д"], length: 60, rng: &rng)
        let tokens = text.split(separator: " ")
        #expect(tokens.count % 2 == 0)
        let firsts = stride(from: 0, to: tokens.count, by: 2).map { tokens[$0] }
        for index in stride(from: 0, to: tokens.count, by: 2) { #expect(tokens[index] == tokens[index + 1], "\(text)") }
        #expect((8...10).contains(Set(firsts).count), "\(text)")
        #expect(Set(firsts).count == firsts.count, "\(text)")
        for word in firsts { #expect(word.contains("р") || word.contains("д"), "\(word)") }
        #expect(onlyAllowed(text, letters))
    }
}

@Test func errorWordsGrowUpToTenForLongerTexts() {
    let letters: Set<Character> = Set("авлдорыпжф")
    var rng = SeededGenerator(seed: 3)
    let short = generator.errorWords(letters: letters, targets: ["р", "д"], length: 10, rng: &rng)
    let long = generator.errorWords(letters: letters, targets: ["р", "д"], length: 1000, rng: &rng)
    #expect(short.split(separator: " ").count == 16)
    #expect(long.split(separator: " ").count == 20)
}

@Test func capitalWordsStartWithCapitalInitial() {
    let allowed: Set<Character> = Set("авлдорыпжфё ")
    for seed in 1...5 {
        var rng = SeededGenerator(seed: UInt64(seed))
        let text = generator.capitalWords(initials: ["в", "д", "ё"], allowed: allowed, length: 120, rng: &rng)
        #expect(text.count >= 120)
        for token in text.split(separator: " ") {
            #expect(["В", "Д"].contains(token.first!), "\(token)")
            #expect(token.dropFirst().allSatisfy(allowed.contains), "\(token)")
        }
    }
}

@Test func wordsMixInExtraWordsWithoutQuotingThem() {
    let enGenerator = TextGenerator(wordList: WordList(words: ["dog", "cat", "sun", "stop", "tons", "nod", "on"]))
    let allowed: Set<Character> = Set("abcdefghijklmnopqrstuvwxyz '")
    var hits = 0
    for seed in 1...20 {
        var rng = SeededGenerator(seed: UInt64(seed))
        let text = enGenerator.words(allowed: allowed, focus: [], length: 100, capitalRate: 0,
                                     extraWords: ["don't", "it's"], rng: &rng)
        let tokens = text.split(separator: " ")
        if tokens.contains("don't") || tokens.contains("it's") { hits += 1 }
        #expect(!tokens.contains { $0.count > 1 && $0.first == "'" && $0.last == "'" }, "\(text)")
        #expect(onlyAllowed(text, allowed))
    }
    #expect(hits > 0)
}

@Test func wordPoolsFollowTheirKind() throws {
    let wordList = try WordList.load(.ru)
    let full = TextGenerator(wordList: wordList)
    let long = full.pool(letters: Language.ru.letters, kind: .long)
    #expect(!long.isEmpty && long.allSatisfy { $0.count >= 7 })
    // `frequent` — первые 1000 слов из подходящих по буквам (а не слова из первой тысячи словаря).
    let letters = Set("аеиовнлкстрмпд")
    let matching = full.wordList.words.filter { $0.allSatisfy(letters.contains) }
    let frequent = full.pool(letters: letters, kind: .frequent)
    #expect(matching.count > 1000)
    #expect(frequent == Array(matching.prefix(1000)))
    #expect(!Set(frequent).isSubset(of: Set(full.wordList.words.prefix(1000))))
    #expect(full.pool(letters: letters, kind: .all) == Array(matching.prefix(2000)))
}

@Test func randomLetterGeneratorsNeverSpellRudeWords() {
    // Буквы, из которых случайно складываются грубые слова: такие токены перебираются заново.
    let letters: [Character] = ["х", "у", "й", "б", "л", "я"]
    let rude = TextGenerator(wordList: WordList(words: ["хуй", "бля", "лук", "уха", "был"]))
    for seed in 1...20 {
        var rng = SeededGenerator(seed: UInt64(seed))
        let texts = [
            rude.drill(keys: letters, length: 300, rng: &rng),
            rude.combos(newKeys: ["х", "б"], allowed: Set(letters).union([" "]), length: 300, rng: &rng),
            rude.capitalWords(initials: ["х", "б"], allowed: Set(letters), length: 300, rng: &rng),
        ]
        for text in texts {
            #expect(!text.split(separator: " ").contains { WordFilter.isBlocked(String($0)) }, "seed \(seed): \(text)")
        }
    }
}

/// Апостроф — не кавычка: в словах, сочетаниях и упражнении на знаки он стоит только внутри слова (don't, it's),
/// а слово в кавычки берёт `"`, если она открыта.
@Test func apostropheStaysInsideWordsAndQuotesUseDoubleQuote() {
    let enGenerator = TextGenerator(wordList: WordList(words: ["dog", "cat", "sun", "stop", "tons", "nod", "complete"]))
    let allowed: Set<Character> = Set("abcdefghijklmnopqrstuvwxyz '")
    var apostrophes = 0, quoted = 0
    func insideWord(_ token: Substring) -> Bool {
        let chars = Array(token)
        return chars.indices.filter { chars[$0] == "'" }.allSatisfy {
            $0 > 0 && $0 < chars.count - 1 && chars[$0 - 1].isLetter && chars[$0 + 1].isLetter
        }
    }
    for seed in 1...20 {
        var rng = SeededGenerator(seed: UInt64(seed))
        let texts = [
            enGenerator.words(allowed: allowed, focus: ["'"], length: 150, capitalRate: 0, rng: &rng),
            enGenerator.combos(newKeys: ["'"], allowed: allowed, length: 150, rng: &rng),
            SymbolDrill.text(language: .en, allowed: allowed, generator: enGenerator, length: 150, rng: &rng),
        ]
        for text in texts {
            #expect(onlyAllowed(text, allowed))
            for token in text.split(separator: " ") where token.contains("'") {
                apostrophes += 1
                #expect(insideWord(token), "«\(token)» в «\(text)»")
            }
        }
        let withQuotes = allowed.union("\"")
        let text = enGenerator.words(allowed: withQuotes, focus: ["\""], length: 150, capitalRate: 0, rng: &rng)
        for token in text.split(separator: " ") where token.contains("'") { #expect(insideWord(token), "«\(token)»") }
        quoted += text.split(separator: " ").filter { $0.count > 2 && $0.first == "\"" && $0.last == "\"" }.count
    }
    #expect(apostrophes > 0 && quoted > 0)
}
