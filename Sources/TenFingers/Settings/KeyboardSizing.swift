/// Пределы размера и сдвига экранной клавиатуры (настройки пользователя).
enum KeyboardSizing {
    static let unitRange: ClosedRange<Double> = 32...56
    static let defaultUnit = 40.0
    static let offsetRange: ClosedRange<Double> = -200...200
    static let defaultOffset = 0.0

    static func clampedUnit(_ value: Double) -> Double { min(max(value, unitRange.lowerBound), unitRange.upperBound) }
    static func clampedOffset(_ value: Double) -> Double { min(max(value, offsetRange.lowerBound), offsetRange.upperBound) }

    /// Промежуток между клавишами в `KeyboardView`.
    static let keySpacing = 4.0

    /// Ширина клавиатуры: ряды занимают 15 единиц и 14 промежутков.
    static func keyboardWidth(unit: Double) -> Double { 15 * unit + 14 * keySpacing }

    /// Высота клавиатуры: 5 рядов по 0,92 единицы и 4 промежутка (как в `KeyboardView`).
    static func keyboardHeight(unit: Double) -> Double { 5 * 0.92 * unit + 4 * keySpacing }

    /// Сдвиг, при котором клавиатура целиком остаётся в видимой области: |сдвиг| не больше половины свободного места.
    /// Если клавиатура не помещается, она стоит по центру.
    static func effectiveOffset(requested: Double, unit: Double, availableWidth: Double) -> Double {
        let limit = max(0, (availableWidth - keyboardWidth(unit: unit)) / 2)
        return min(max(clampedOffset(requested), -limit), limit)
    }
}
