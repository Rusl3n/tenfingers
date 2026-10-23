import Foundation
import Testing
@testable import TypingCore

@Test func russianAlphabetHas33Letters() {
    #expect(Language.ru.letters.count == 33)
    #expect(Language.ru.letters.contains("ё"))
}

@Test func englishAlphabetHas26Letters() {
    #expect(Language.en.letters.count == 26)
}

@Test func languageFromInputSourceCode() {
    #expect(Language(inputSourceLanguage: "ru") == .ru)
    #expect(Language(inputSourceLanguage: "en-US") == .en)
    #expect(Language(inputSourceLanguage: "de") == nil)
}

@Test func resourcesBundleIsFound() throws {
    let url = try CoreResources.url("CREDITS", "md")
    #expect(FileManager.default.fileExists(atPath: url.path))
}

@Test func missingResourceThrows() {
    #expect(throws: CoreResourceError.missing("nope.json")) {
        try CoreResources.url("nope", "json")
    }
}
