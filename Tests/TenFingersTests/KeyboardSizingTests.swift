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

@Test func keyboardWidthIsProportionalToUnit() {
    // Клавиатура рисуется в базовом размере (656 при 40) и масштабируется: 16,4 · unit.
    #expect(KeyboardSizing.keyboardWidth(unit: 40) == 656)
    #expect(abs(KeyboardSizing.keyboardWidth(unit: 32) - 524.8) < 0.001)
    #expect(abs(KeyboardSizing.keyboardWidth(unit: 56) - 918.4) < 0.001)
}

@Test func keyboardScaleIsUnitOverBase() {
    #expect(KeyboardSizing.baseUnit == 40)
    #expect(KeyboardSizing.scale(unit: 40) == 1)
    #expect(abs(KeyboardSizing.scale(unit: 56) - 1.4) < 0.000_001)
    // Размер вне пределов зажимается: 32 / 40.
    #expect(abs(KeyboardSizing.scale(unit: 10) - 0.8) < 0.000_001)
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

@Test func keyboardHeightIsProportionalToUnit() {
    // При 40: 5 рядов по 0,92 единицы и 4 промежутка = 200; дальше пропорционально, 5 · unit.
    #expect(abs(KeyboardSizing.keyboardHeight(unit: 40) - 200) < 0.001)
    #expect(abs(KeyboardSizing.keyboardHeight(unit: 56) - 280) < 0.001)
}
