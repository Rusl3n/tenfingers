import Testing
@testable import TypingCore

@Test(arguments: Language.allCases)
func bundledWordListsAreLargeAndClean(language: Language) throws {
    let list = try WordList.load(language)
    #expect(list.words.count > 15_000)
    for word in list.words {
        #expect(word.count >= 2 && word.count <= 12)
        #expect(word.allSatisfy(language.letters.contains), "\(word)")
    }
}

@Test func filtersByAllowedLettersKeepingOrder() {
    let list = WordList(words: ["вал", "дом", "лава", "ал"])
    #expect(list.words(using: Set("авл")) == ["вал", "лава", "ал"])
}
