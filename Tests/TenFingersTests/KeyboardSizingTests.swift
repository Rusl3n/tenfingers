import Testing
@testable import TenFingers

@Test func keyboardSizingClampsValues() {
    #expect(KeyboardSizing.clampedUnit(10) == 32)
    #expect(KeyboardSizing.clampedUnit(44) == 44)
    #expect(KeyboardSizing.clampedUnit(90) == 56)
    #expect(KeyboardSizing.clampedOffset(-500) == -200)
    #expect(KeyboardSizing.clampedOffset(35) == 35)
    #expect(KeyboardSizing.clampedOffset(500) == 200)
}

@Test func keyboardWidthIsFifteenUnitsPlusGaps() {
    #expect(KeyboardSizing.keyboardWidth(unit: 40) == 656)
    #expect(KeyboardSizing.keyboardWidth(unit: 32) == 536)
}

@Test func effectiveOffsetIsCenteredWhenKeyboardDoesNotFit() {
    #expect(KeyboardSizing.effectiveOffset(requested: 150, unit: 40, availableWidth: 600) == 0)
    #expect(KeyboardSizing.effectiveOffset(requested: -150, unit: 40, availableWidth: 656) == 0)
}

@Test func effectiveOffsetKeepsRequestedValueWhenThereIsRoom() {
    // Свободно по 100 pt с каждой стороны.
    #expect(KeyboardSizing.effectiveOffset(requested: 60, unit: 40, availableWidth: 856) == 60)
    #expect(KeyboardSizing.effectiveOffset(requested: -60, unit: 40, availableWidth: 856) == -60)
}

@Test func effectiveOffsetIsLimitedSymmetrically() {
    #expect(KeyboardSizing.effectiveOffset(requested: 180, unit: 40, availableWidth: 756) == 50)
    #expect(KeyboardSizing.effectiveOffset(requested: -180, unit: 40, availableWidth: 756) == -50)
}

@Test func effectiveOffsetStillClampsToSettingsRange() {
    #expect(KeyboardSizing.effectiveOffset(requested: 900, unit: 40, availableWidth: 5000) == 200)
    #expect(KeyboardSizing.effectiveOffset(requested: -900, unit: 40, availableWidth: 5000) == -200)
}

@Test func keyboardHeightIsFiveRowsPlusGaps() {
    // 5 рядов по 0.92 единицы и 4 промежутка.
    #expect(abs(KeyboardSizing.keyboardHeight(unit: 40) - (5 * 36.8 + 16)) < 0.001)
}
