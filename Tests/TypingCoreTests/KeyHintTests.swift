import Testing
@testable import TypingCore

private let snap = LayoutSnapshot(id: "t", language: .ru, shape: .ansi,
                                  plain: [3: "а", 22: "6"], shifted: [3: "А", 22: ":"])

@Test func fullHintAlwaysHighlights() {
    let h = KeyHint.highlight(expected: "а", snapshot: snap, hint: .full, positionHasError: false, errorFlash: false)
    #expect(h == KeyHighlight(keyCode: 3, shiftKeyCode: nil, isError: false))
}

@Test func shiftedCharacterHighlightsOppositeShift() {
    let h = KeyHint.highlight(expected: ":", snapshot: snap, hint: .full, positionHasError: false, errorFlash: true)
    #expect(h == KeyHighlight(keyCode: 22, shiftKeyCode: KeyboardGeometry.leftShift, isError: true))
}

@Test func onErrorHintOnlyAfterMistake() {
    #expect(KeyHint.highlight(expected: "а", snapshot: snap, hint: .onError, positionHasError: false, errorFlash: false) == nil)
    #expect(KeyHint.highlight(expected: "а", snapshot: snap, hint: .onError, positionHasError: true, errorFlash: true) != nil)
}

@Test func hiddenHintNeverHighlights() {
    #expect(KeyHint.highlight(expected: "а", snapshot: snap, hint: .hidden, positionHasError: true, errorFlash: true) == nil)
}

@Test func reachDescriptions() {
    // Язык системы в тестовом процессе не определён (бандл следует языку хост-процесса), поэтому язык задан явно.
    func ru(_ code: UInt16) -> String { ReachDescription.describe(keyCode: code, shape: .ansi, localization: "ru") }
    #expect(ru(3) == "исходная позиция")         // А
    #expect(ru(5) == "вправо")                   // П
    #expect(ru(15) == "вверх")                   // К
    #expect(ru(17) == "вверх и вправо")          // Е
    #expect(ru(11) == "вниз и вправо")           // И
    #expect(ru(21) == "на 2 ряда вверх и влево") // 4
}

// MARK: - Пробел: большой палец противоположной руки

/// а — левый указательный (3), о — правый указательный (38), Ж/ж — правый мизинец (41).
private let thumbSnap = LayoutSnapshot(id: "t", language: .ru, shape: .ansi,
                                       plain: [3: "а", 38: "о", 41: "ж"], shifted: [3: "А", 38: "О", 41: "Ж"])

@Test func spaceAfterLeftHandIsRightThumb() {
    #expect(SpaceThumb.preferred(previous: "а", snapshot: thumbSnap) == .right)
}

@Test func spaceAfterRightHandIsLeftThumb() {
    #expect(SpaceThumb.preferred(previous: "о", snapshot: thumbSnap) == .left)
}

@Test func spaceAfterSpaceOrNothingIsAnyThumb() {
    #expect(SpaceThumb.preferred(previous: " ", snapshot: thumbSnap) == nil)
    #expect(SpaceThumb.preferred(previous: nil, snapshot: thumbSnap) == nil)
    #expect(SpaceThumb.preferred(previous: "z", snapshot: thumbSnap) == nil) // нет в раскладке
}

@Test func spaceAfterShiftedCharacterFollowsMainKeyHand() {
    #expect(SpaceThumb.preferred(previous: "А", snapshot: thumbSnap) == .right)
    #expect(SpaceThumb.preferred(previous: "Ж", snapshot: thumbSnap) == .left)
}

@Test func highlightCarriesSpaceThumbWhenEnabled() {
    let on = KeyHint.highlight(expected: " ", snapshot: thumbSnap, hint: .full, positionHasError: false,
                               errorFlash: false, previous: "а", spaceThumb: true)
    #expect(on == KeyHighlight(keyCode: KeyboardGeometry.space, shiftKeyCode: nil, isError: false, spaceThumb: .right))
    let off = KeyHint.highlight(expected: " ", snapshot: thumbSnap, hint: .full, positionHasError: false,
                                errorFlash: false, previous: "а", spaceThumb: false)
    #expect(off?.spaceThumb == nil)
}

@Test func spaceThumbOnlyForSpaceAndRespectsHintLevel() {
    let letter = KeyHint.highlight(expected: "о", snapshot: thumbSnap, hint: .full, positionHasError: false,
                                   errorFlash: false, previous: "а", spaceThumb: true)
    #expect(letter?.spaceThumb == nil)
    #expect(KeyHint.highlight(expected: " ", snapshot: thumbSnap, hint: .onError, positionHasError: false,
                              errorFlash: false, previous: "а", spaceThumb: true) == nil)
    #expect(KeyHint.highlight(expected: " ", snapshot: thumbSnap, hint: .onError, positionHasError: true,
                              errorFlash: true, previous: "о", spaceThumb: true)?.spaceThumb == .left)
}
