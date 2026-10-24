import Foundation
import SwiftData
import Testing
import TypingCore
@testable import TenFingers

private struct Fixture {
    let allowed: Set<Character>
    let generator: TextGenerator
    let library: [LibraryText]

    init(_ language: Language) throws {
        allowed = try CourseCatalog.load(language).typeableCharacters
        generator = TextGenerator(wordList: try WordList.load(language))
        library = try TextLibrary.load(language)
    }
}

@Test(arguments: Language.allCases)
func everySourceGivesNonEmptyTypeableText(language: Language) throws {
    let fixture = try Fixture(language)
    var sources: [PracticeSource] = [.frequentWords, .symbols]
    sources += fixture.library.map(PracticeSource.library)
    for source in sources {
        var rng = SeededGenerator(seed: 5)
        let result = PracticeTextFactory.text(for: source, language: language, allowed: fixture.allowed,
                                              generator: fixture.generator, custom: nil, rng: &rng)
        #expect(!result.text.isEmpty, "\(source)")
        #expect(result.text.allSatisfy(fixture.allowed.contains), "\(source)")
        #expect(result.nextOffset == nil)
    }
}

@Test(arguments: Language.allCases)
func frequentWordsAndSymbolsHaveEnoughText(language: Language) throws {
    let fixture = try Fixture(language)
    for source in [PracticeSource.frequentWords, .symbols] {
        var rng = SeededGenerator(seed: 1)
        let text = PracticeTextFactory.text(for: source, language: language, allowed: fixture.allowed,
                                            generator: fixture.generator, custom: nil, rng: &rng).text
        #expect(text.count >= 280, "\(source): \(text.count)")
    }
}

@Test(arguments: Language.allCases)
func customTextAdvancesToTheEnd(language: Language) throws {
    let fixture = try Fixture(language)
    let body = TextNormalizer.typeable(fixture.library.map(\.text).joined(separator: " "), allowed: fixture.allowed)
    #expect(body.count > 1000)
    var offset = 0
    var portions = 0
    var rng = SeededGenerator(seed: 2)
    while offset < body.count {
        let result = PracticeTextFactory.text(for: .custom(UUID()), language: language, allowed: fixture.allowed,
                                              generator: fixture.generator, custom: (body, offset), rng: &rng)
        let next = try #require(result.nextOffset)
        #expect(next > offset)
        #expect(!result.text.isEmpty)
        #expect(result.text.allSatisfy(fixture.allowed.contains))
        offset = next
        portions += 1
        #expect(portions < 200)
    }
    #expect(offset == body.count)
    // Дальше текста нет: порция пустая, смещение остаётся в конце.
    let done = PracticeTextFactory.text(for: .custom(UUID()), language: language, allowed: fixture.allowed,
                                        generator: fixture.generator, custom: (body, offset), rng: &rng)
    #expect(done.text.isEmpty)
    #expect(done.nextOffset == body.count)
}

@Test func customTextOffsetOutOfRangeIsClamped() throws {
    let fixture = try Fixture(.en)
    var rng = SeededGenerator(seed: 2)
    let body = "hello world again"
    let past = PracticeTextFactory.text(for: .custom(UUID()), language: .en, allowed: fixture.allowed,
                                        generator: fixture.generator, custom: (body, 999), rng: &rng)
    #expect(past.text.isEmpty && past.nextOffset == body.count)
    let negative = PracticeTextFactory.text(for: .custom(UUID()), language: .en, allowed: fixture.allowed,
                                            generator: fixture.generator, custom: (body, -5), rng: &rng)
    #expect(negative.text == body)
}

@Test func customSourceWithoutBodyGivesNothing() throws {
    let fixture = try Fixture(.ru)
    var rng = SeededGenerator(seed: 2)
    let result = PracticeTextFactory.text(for: .custom(UUID()), language: .ru, allowed: fixture.allowed,
                                          generator: fixture.generator, custom: nil, rng: &rng)
    #expect(result.text.isEmpty && result.nextOffset == nil)
}

// MARK: - Свой текст

@Test func draftTooShortAfterNormalizationIsRejected() {
    let draft = CustomTextDraft.make(title: "x", raw: "✓✓✓ ab ✓✓✓", fallback: .en) { _ in Set("ab ") }
    #expect(draft == .failure(.tooShort))
}

@Test func draftDetectsLanguageAndNormalizes() throws {
    let allowed: (Language) -> Set<Character> = { (try? CourseCatalog.load($0).typeableCharacters) ?? [] }
    let raw = "«Съешь ещё этих мягких французских булок»,\u{2009}— сказал он.\n\nЕщё чаю!"
    let draft = try CustomTextDraft.make(title: "  Заметки  ", raw: raw, fallback: .en, allowed: allowed).get()
    #expect(draft.language == .ru)
    #expect(draft.title == "Заметки")
    #expect(draft.body == "\"Съешь ещё этих мягких французских булок\", - сказал он. Ещё чаю!")
}

@Test func draftWithoutLettersUsesFallbackLanguage() throws {
    let allowed: (Language) -> Set<Character> = { (try? CourseCatalog.load($0).typeableCharacters) ?? [] }
    let draft = try CustomTextDraft.make(title: "", raw: "1234 5678 9012 3456 7890", fallback: .en, allowed: allowed).get()
    #expect(draft.language == .en)
    #expect(draft.title == "1234 5678 9012 3456 7890")
}

@Test func draftEmptyTitleTakesTheStartOfText() throws {
    let allowed: (Language) -> Set<Character> = { (try? CourseCatalog.load($0).typeableCharacters) ?? [] }
    let long = String(repeating: "lorem ipsum ", count: 20)
    let draft = try CustomTextDraft.make(title: " ", raw: long, fallback: .en, allowed: allowed).get()
    #expect(draft.title.count <= 41 && draft.title.hasPrefix("lorem ipsum"))
}

@MainActor @Test func advanceCustomTextClampsOffset() throws {
    let container = try ModelStore.makeContainer(inMemory: true)
    let recorder = ResultRecorder(context: container.mainContext, dayStartHour: 4)
    let text = CustomText(title: "t", body: "twelve chars", language: "en")
    container.mainContext.insert(text)
    recorder.advanceCustomText(text, to: 500)
    #expect(text.offset == 12)
    recorder.advanceCustomText(text, to: -3)
    #expect(text.offset == 0)
    recorder.advanceCustomText(text, to: 7)
    #expect(text.offset == 7)
}

@Test func customProgressIsClamped() {
    #expect(CustomTextDraft.progress(offset: 50, length: 200) == 0.25)
    #expect(CustomTextDraft.progress(offset: 900, length: 200) == 1)
    #expect(CustomTextDraft.progress(offset: -1, length: 200) == 0)
    #expect(CustomTextDraft.progress(offset: 5, length: 0) == 0)
}

// MARK: - Ссылка на источник

@Test func wikisourceRawUrlBecomesHumanPage() throws {
    let raw = "https://ru.wikisource.org/w/index.php?title=%D0%9C%D1%83%D0%BC%D1%83_%28%D0%A2%D1%83%D1%80%D0%B3%D0%B5%D0%BD%D0%B5%D0%B2%29&action=raw"
    let url = try #require(SourceLink.pageURL(for: raw))
    #expect(url.host == "ru.wikisource.org")
    #expect(url.path(percentEncoded: false) == "/wiki/Муму_(Тургенев)")
    #expect(url.query == nil)
    #expect(!url.absoluteString.contains("action=raw"))
}

@Test func wikisourceSubpageKeepsSlashes() throws {
    let raw = "https://ru.wikisource.org/w/index.php?title=%D0%93%D0%B5%D1%80%D0%BE%D0%B9_%D0%BD%D0%B0%D1%88%D0%B5%D0%B3%D0%BE_%D0%B2%D1%80%D0%B5%D0%BC%D0%B5%D0%BD%D0%B8_%28%D0%9B%D0%B5%D1%80%D0%BC%D0%BE%D0%BD%D1%82%D0%BE%D0%B2%29/%D0%A1%D0%9E/%D0%91%D1%8D%D0%BB%D0%B0&action=raw"
    let url = try #require(SourceLink.pageURL(for: raw))
    #expect(url.path(percentEncoded: false) == "/wiki/Герой_нашего_времени_(Лермонтов)/СО/Бэла")
}

@Test func gutenbergTextUrlBecomesBookPage() throws {
    let url = try #require(SourceLink.pageURL(for: "https://www.gutenberg.org/cache/epub/1342/pg1342.txt"))
    #expect(url.absoluteString == "https://www.gutenberg.org/ebooks/1342")
}

@Test func otherUrlsStayAsIs() throws {
    let url = try #require(SourceLink.pageURL(for: "https://example.org/book"))
    #expect(url.absoluteString == "https://example.org/book")
    #expect(SourceLink.pageURL(for: "") == nil)
}

@Test(arguments: Language.allCases)
func everyLibrarySourceHasAHumanLink(language: Language) throws {
    for item in try TextLibrary.load(language) {
        let url = try #require(SourceLink.pageURL(for: item.source), "\(item.id)")
        #expect(url.scheme == "https")
        #expect(!url.absoluteString.contains("action=raw") && !url.absoluteString.hasSuffix(".txt"), "\(item.id)")
    }
}

@Test func textFileDecoderReadsUtf8AndWindows1251() throws {
    let word = "Привет"
    #expect(TextFileDecoder.decode(Data(word.utf8)) == word)
    let cp1251 = try #require(word.data(using: .windowsCP1251))
    #expect(cp1251 != Data(word.utf8))
    #expect(TextFileDecoder.decode(cp1251) == word)
    #expect(TextFileDecoder.decode(Data()) == "")
}

@Test func textFileDecoderReadsFilesInSeveralEncodings() throws {
    let word = "Привет, мир"
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let samples: [(String, String.Encoding)] = [("u8", .utf8), ("cp", .windowsCP1251), ("u16", .utf16)]
    for (name, encoding) in samples {
        let url = directory.appendingPathComponent("\(name).txt")
        try #require(word.data(using: encoding)).write(to: url)
        #expect(TextFileDecoder.read(url) == word, "\(name)")
    }
    #expect(TextFileDecoder.read(directory.appendingPathComponent("missing.txt")) == nil)
}

@Test func practiceSourceRecordNames() throws {
    let item = try #require(try TextLibrary.load(.ru).first)
    #expect(PracticeSource.library(item).recordName == "library:\(item.id)")
    #expect(PracticeSource.custom(UUID()).recordName == "custom")
    #expect(PracticeSource.symbols.recordName == "symbols")
    #expect(PracticeSource.frequentWords.recordName == "words")
}

/// UTF-16 без BOM: «Привет» в UTF-16LE — это байты 1F 04 40 04 …, формально корректный UTF-8 из управляющих символов.
@Test func textFileDecoderReadsUtf16WithoutBom() throws {
    let word = "Привет"
    let little = try #require(word.data(using: .utf16LittleEndian))
    #expect(little.first != 0xFF)
    #expect(TextFileDecoder.decode(little) == word)
    let big = try #require(word.data(using: .utf16BigEndian))
    #expect(TextFileDecoder.decode(big) == word)
    let english = try #require("Hello, world".data(using: .utf16LittleEndian))
    #expect(TextFileDecoder.decode(english) == "Hello, world")

    let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).txt")
    defer { try? FileManager.default.removeItem(at: url) }
    try little.write(to: url)
    #expect(TextFileDecoder.read(url) == word)
}

@Test func textFileDecoderRejectsControlCharacters() throws {
    #expect(TextFileDecoder.decode(Data([0x01, 0x02, 0x03, 0x41, 0x42, 0x43, 0x44, 0x45, 0x46, 0x47])) == nil)
    #expect(TextFileDecoder.decode(Data("строка\nещё\tтаб\r\n".utf8)) == "строка\nещё\tтаб\r\n")
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).bin")
    defer { try? FileManager.default.removeItem(at: url) }
    try Data((0..<400).map { UInt8($0 % 32) }).write(to: url)
    #expect(TextFileDecoder.read(url) == nil)
}

@Test func cancellingCustomTextAsksOnlyWhenTextIsTyped() {
    #expect(!CustomTextEditor.cancelNeedsConfirmation(text: ""))
    #expect(!CustomTextEditor.cancelNeedsConfirmation(text: "  \n\t"))
    #expect(CustomTextEditor.cancelNeedsConfirmation(text: "Мой текст"))
}
