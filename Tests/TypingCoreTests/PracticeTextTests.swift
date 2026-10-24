import Testing
@testable import TypingCore

@Test func normalizerMapsTypographyToKeyboard() {
    let allowed = try! CourseCatalog.load(.ru).typeableCharacters
    let text = TextNormalizer.typeable("«Ёлка» — это… ель!\n\tНет?", allowed: allowed)
    #expect(text == "\"ёлка\" - это... ель! Нет?")
}

@Test func normalizerDropsUntypeableAndCollapsesSpaces() {
    let allowed = Set("abc ")
    #expect(TextNormalizer.typeable("a  b ✓ c", allowed: allowed) == "a b c")
}

@Test func dominantLanguage() {
    #expect(TextNormalizer.dominantLanguage("Привет, мир! hello") == .ru)
    #expect(TextNormalizer.dominantLanguage("Hello, world! да") == .en)
    #expect(TextNormalizer.dominantLanguage("12345 !!!") == nil)
}

@Test func chunkerSplitsAtWordBoundary() {
    let text = String(repeating: "слово ", count: 200).trimmingCharacters(in: .whitespaces)
    let first = TextChunker.chunk(text, from: 0, size: 500)
    #expect(first.text.count <= 500 && first.text.count > 400)
    #expect(!first.text.hasSuffix(" ") && !first.text.hasPrefix(" "))
    let second = TextChunker.chunk(text, from: first.nextOffset, size: 500)
    #expect(second.text.hasPrefix("слово"))
    let last = TextChunker.chunk(text, from: text.count - 3, size: 500)
    #expect(last.nextOffset == text.count)
}

@Test(arguments: Language.allCases)
func symbolDrillUsesOnlyTypeableCharacters(language: Language) throws {
    let allowed = try CourseCatalog.load(language).typeableCharacters
    let generator = TextGenerator(wordList: try WordList.load(language))
    var rng = SeededGenerator(seed: 9)
    let text = SymbolDrill.text(language: language, allowed: allowed, generator: generator, length: 400, rng: &rng)
    #expect(text.count >= 400)
    #expect(text.allSatisfy(allowed.contains))
    #expect(text.contains { $0.isNumber })
    #expect(Set(text.filter { !$0.isLetter && !$0.isNumber && $0 != " " }).count >= 6)
}

@Test(arguments: Language.allCases)
func libraryTextsAreTypeable(language: Language) throws {
    let allowed = try CourseCatalog.load(language).typeableCharacters
    let texts = try TextLibrary.load(language)
    #expect(texts.count >= 10)
    #expect(Set(texts.map(\.id)).count == texts.count)
    for item in texts {
        #expect(!item.title.isEmpty && !item.author.isEmpty, "\(item.id): нет названия или автора")
        #expect(item.source.hasPrefix("https://"), "\(item.id): нет источника")
        let normalized = TextNormalizer.typeable(item.text, allowed: allowed)
        #expect(normalized.count >= 250 && normalized.count <= 1200, "\(item.id): \(normalized.count)")
        #expect(Double(normalized.count) / Double(item.text.count) > 0.97, "\(item.id): много невводимых символов")
    }
}

@Test func normalizerMapsUnicodeSpacesAndRemovesZeroWidth() {
    let allowed = Set("abc ")
    #expect(TextNormalizer.typeable("a\u{2009}b\u{202F}c\u{2003}a\u{3000}b\u{200B}c", allowed: allowed) == "a b c a bc")
    #expect(TextNormalizer.typeable("\u{200B}\u{FEFF}a\u{2002}\u{2002}b", allowed: allowed) == "a b")
}

@Test func normalizerStripsCombiningMarksOnlyWhereNeeded() throws {
    let ru = try CourseCatalog.load(.ru).typeableCharacters
    let en = try CourseCatalog.load(.en).typeableCharacters
    // Ударение: «а» + U+0301 → «а».
    #expect(TextNormalizer.typeable("за\u{0301}мок", allowed: ru) == "замок")
    // «й» и «ё» входят в раскладку и остаются, даже в разложенном виде.
    #expect(TextNormalizer.typeable("и\u{0306}е\u{0308}", allowed: ru) == "йё")
    #expect(TextNormalizer.typeable("cafe\u{0301} caf\u{00E9}", allowed: en) == "cafe cafe")
    #expect(TextNormalizer.typeable("na\u{00EF}ve", allowed: en) == "naive")
}

@Test func chunkerEdgeCases() {
    #expect(TextChunker.chunk("", from: 0).text.isEmpty)
    #expect(TextChunker.chunk("", from: 0).nextOffset == 0)
    let past = TextChunker.chunk("слово", from: 99)
    #expect(past.text.isEmpty && past.nextOffset == 5)
    // Слово длиннее порции режется по размеру.
    let long = String(repeating: "а", count: 30)
    let cut = TextChunker.chunk(long, from: 0, size: 10)
    #expect(cut.text.count == 10 && cut.nextOffset == 10)
}

@Test func chunkerKeepsWordWhenSpaceFollowsTheCut() {
    // Порция «aaaa bbbb» ровно по границе слова: «bbbb» остаётся в ней, а не уходит в следующую.
    let first = TextChunker.chunk("aaaa bbbb cccc", from: 0, size: 9)
    #expect(first.text == "aaaa bbbb")
    #expect(first.nextOffset == 9)
    #expect(TextChunker.chunk("aaaa bbbb cccc", from: first.nextOffset, size: 9).text == "cccc")
}
