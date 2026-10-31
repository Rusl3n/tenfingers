import Testing
import TypingCore
@testable import TenFingers

@MainActor @Test func russianWinShiftSixIsColon() throws {
    let source = try #require(KeyboardLayoutService.source(withID: "com.apple.keylayout.RussianWin"))
    let snap = KeyboardLayoutService.snapshot(for: source, shape: .ansi)
    #expect(snap.language == .ru)
    #expect(snap.plain[0] == "ф")
    #expect(snap.shifted[22] == ":")
    #expect(snap.keyPress(for: ":") == KeyPress(keyCode: 22, shift: true))
}

@MainActor @Test func abcShiftSixIsCaret() throws {
    let source = try #require(KeyboardLayoutService.source(withID: "com.apple.keylayout.ABC"))
    let snap = KeyboardLayoutService.snapshot(for: source, shape: .ansi)
    #expect(snap.language == .en)
    #expect(snap.shifted[22] == "^")
    #expect(snap.keyPress(for: "A") == KeyPress(keyCode: 0, shift: true))
}

@Test func fingerOfMapsLanguageLettersThroughLayout() {
    let snapshot = LayoutSnapshot(id: "t", language: .ru, shape: .ansi,
                                  plain: [0: "ф", 3: "а", 38: "о", 49: " "], shifted: [:])
    let map = KeyboardLayoutService.fingerOf(snapshot: snapshot, language: .ru)
    #expect(map == ["ф": .leftPinky, "а": .leftIndex, "о": .rightIndex])
    // Раскладка другого языка: букв курса в ней нет — карта пуста.
    #expect(KeyboardLayoutService.fingerOf(snapshot: snapshot, language: .en).isEmpty)
}
