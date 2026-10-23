import Testing
@testable import TypingCore

private let sample = LayoutSnapshot(
    id: "test", language: .ru, shape: .ansi,
    plain: [0: "ф", 22: "6", 50: "ё", 44: "."],
    shifted: [0: "Ф", 22: ":", 50: "Ё", 44: ","]
)

@Test func findsPlainAndShiftedCharacters() {
    #expect(sample.keyPress(for: "ф") == KeyPress(keyCode: 0, shift: false))
    #expect(sample.keyPress(for: "Ф") == KeyPress(keyCode: 0, shift: true))
    #expect(sample.keyPress(for: ":") == KeyPress(keyCode: 22, shift: true))
    #expect(sample.keyPress(for: ",") == KeyPress(keyCode: 44, shift: true))
}

@Test func spaceAlwaysMapsToSpaceBar() {
    #expect(sample.keyPress(for: " ") == KeyPress(keyCode: 49, shift: false))
}

@Test func unknownCharacterIsNil() {
    #expect(sample.keyPress(for: "z") == nil)
}

@Test func onlyKeysOfCurrentShapeAreSearched() {
    // keyCode 10 нет в ANSI-геометрии, поэтому «ё» ищется на 50
    let snap = LayoutSnapshot(id: "t", language: .ru, shape: .ansi,
                              plain: [10: "ё", 50: "ё"], shifted: [:])
    #expect(snap.keyPress(for: "ё")?.keyCode == 50)
}

@Test func missingCharactersAreSortedUniqueAndIgnoreSpace() {
    #expect(sample.missingCharacters(in: "фz ё.qzФ ") == ["q", "z"])
    #expect(sample.missingCharacters(in: "ф ё").isEmpty)
    #expect(sample.missingCharacters(in: [Character]()).isEmpty)
}
