import Testing
import TypingCore
@testable import TenFingers

/// Каждый символ курса должен печататься в стандартной раскладке своего языка.
@MainActor
@Test(arguments: [(Language.ru, "com.apple.keylayout.RussianWin"), (Language.en, "com.apple.keylayout.ABC")])
func everyCourseCharacterIsTypeable(language: Language, layoutID: String) throws {
    let source = try #require(KeyboardLayoutService.source(withID: layoutID))
    let snap = KeyboardLayoutService.snapshot(for: source, shape: .ansi)
    let course = try CourseCatalog.load(language)
    var characters = Set(course.lessons.flatMap(\.newCharacters))
    // Shift+ё в RussianWin даёт U+00CB, а не Ё; генератор Ё никогда не создаёт, поэтому её не требуем.
    characters.formUnion(language.letters.subtracting(["ё"]).flatMap { $0.uppercased() })
    for character in characters {
        #expect(snap.keyPress(for: character) != nil, "«\(character)» не найден в \(layoutID)")
    }
}
