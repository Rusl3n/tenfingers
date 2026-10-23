import Testing
@testable import TypingCore

@Test(arguments: [KeyboardShape.ansi, .iso])
func everyRowIsFifteenUnitsWide(shape: KeyboardShape) {
    for row in KeyboardGeometry.rows(for: shape).dropLast() {
        #expect(row.reduce(0) { $0 + $1.width } == 15)
    }
}

@Test func ansiHasGraveTopLeftAndIsoHasSection() {
    #expect(KeyboardGeometry.rows(for: .ansi)[0].first?.keyCode == 50)
    #expect(KeyboardGeometry.rows(for: .iso)[0].first?.keyCode == 10)
    #expect(KeyboardGeometry.rows(for: .iso)[3].map(\.keyCode).prefix(2) == [56, 50])
}

@Test func characterKeysExcludeModifiersAndSpace() {
    let keys = KeyboardGeometry.characterKeys(for: .ansi)
    #expect(keys.count == 47)
    #expect(!keys.contains(49))
    #expect(!keys.contains(56))
    #expect(keys.contains(22))
    #expect(KeyboardGeometry.characterKeys(for: .iso).count == 48)
}

@Test func fingersFollowClassicScheme() {
    #expect(FingerMap.finger(for: 3) == .leftIndex)     // F / А
    #expect(FingerMap.finger(for: 5) == .leftIndex)     // G / П
    #expect(FingerMap.finger(for: 38) == .rightIndex)   // J / О
    #expect(FingerMap.finger(for: 22) == .rightIndex)   // 6
    #expect(FingerMap.finger(for: 0) == .leftPinky)     // A / Ф
    #expect(FingerMap.finger(for: 39) == .rightPinky)   // ' / Э
    #expect(FingerMap.finger(for: 49) == .thumb)
    #expect(FingerMap.finger(for: 50) == .leftPinky)
}

@Test func everyCharacterKeyHasAFinger() {
    for shape in [KeyboardShape.ansi, .iso] {
        for code in KeyboardGeometry.characterKeys(for: shape) {
            #expect(FingerMap.finger(for: code) != nil, "keyCode \(code)")
        }
    }
}

@Test func shiftIsPressedByOppositeHand() {
    #expect(FingerMap.shiftKey(for: 0) == KeyboardGeometry.rightShift)
    #expect(FingerMap.shiftKey(for: 38) == KeyboardGeometry.leftShift)
}

@Test func positionOfKeys() {
    let f = KeyboardGeometry.position(of: 3, shape: .ansi)
    #expect(f?.row == 2)
    #expect(f?.x == 5.25)
    #expect(KeyboardGeometry.position(of: 999, shape: .ansi) == nil)
}
