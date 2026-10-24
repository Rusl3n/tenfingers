import Testing
@testable import TypingCore

@Test func textTraitsFollowCharacters() {
    #expect(TextTraits.of("привет мир") == [])
    #expect(TextTraits.of("Привет") == [.capitals])
    #expect(TextTraits.of("а, б.") == [.punctuation])
    #expect(TextTraits.of("в 2026 году") == [.digits])
    #expect(TextTraits.of("Ёлка: 3 шт.") == [.capitals, .punctuation, .digits])
    #expect(TextTraits.of("a+b=c") == [.punctuation])
    #expect(TextTraits.of("№ 5") == [.punctuation, .digits])
    #expect(TextTraits.of("don't") == [.punctuation])
}

@Test func connectedTextComesFromLibraryAndCustomSources() {
    #expect(TextTraits.connected(source: "custom") == .connected)
    #expect(TextTraits.connected(source: "library:pushkin-1") == .connected)
    #expect(TextTraits.connected(source: "words") == [])
    #expect(TextTraits.connected(source: nil) == [])
}

@Test func textTraitsMaskMatchesStoredBits() {
    #expect(TextTraits.capitals.rawValue == 1 && TextTraits.punctuation.rawValue == 2)
    #expect(TextTraits.digits.rawValue == 4 && TextTraits.connected.rawValue == 8)
    #expect(([.capitals, .digits] as TextTraits).rawValue == 5)
}
