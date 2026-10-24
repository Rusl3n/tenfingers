import Foundation

/// Пределы размера и сдвига экранной клавиатуры (настройки пользователя).
enum KeyboardSizing {
    static let unitRange: ClosedRange<Double> = 32...56
    static let defaultUnit = 40.0
    static let offsetRange: ClosedRange<Double> = -200...200
    static let defaultOffset = 0.0
    /// Размер, в котором клавиатура рисуется; другие размеры получаются масштабом (`ScaledKeyboardView`).
    static let baseUnit = 40.0

    static func clampedUnit(_ value: Double) -> Double { min(max(value, unitRange.lowerBound), unitRange.upperBound) }
    static func clampedOffset(_ value: Double) -> Double { min(max(value, offsetRange.lowerBound), offsetRange.upperBound) }

    /// Во сколько раз клавиатура размера `unit` больше базовой.
    static func scale(unit: Double) -> Double { clampedUnit(unit) / baseUnit }

    /// Промежуток между клавишами в `KeyboardView`.
    static let keySpacing = 4.0

    // Клавиатура рисуется в базовом размере и масштабируется, поэтому размеры пропорциональны unit:
    // ширина 16,4·unit (656 при 40), высота 5·unit (200 при 40).

    /// Ширина клавиатуры: в базовом размере ряды занимают 15 единиц и 14 промежутков.
    static func keyboardWidth(unit: Double) -> Double { (15 * baseUnit + 14 * keySpacing) * unit / baseUnit }

    /// Высота клавиатуры: в базовом размере 5 рядов по 0,92 единицы и 4 промежутка (как в `KeyboardView`).
    static func keyboardHeight(unit: Double) -> Double { (5 * 0.92 * baseUnit + 4 * keySpacing) * unit / baseUnit }

    /// Сдвиг, при котором клавиатура целиком остаётся в видимой области: |сдвиг| не больше половины свободного места.
    /// Если клавиатура не помещается, она стоит по центру.
    static func effectiveOffset(requested: Double, unit: Double, availableWidth: Double) -> Double {
        let limit = max(0, (availableWidth - keyboardWidth(unit: unit)) / 2)
        return min(max(clampedOffset(requested), -limit), limit)
    }
}

/// «Клавиатура по умолчанию»: размер и сдвиг. Значения записываются (а не удаляются ключи), чтобы `@AppStorage`
/// во вьюхах, а с ним миниатюра и пружина, сработали сразу.
enum KeyboardSettingsDefaults {
    static func isDefault(unit: Double, offset: Double) -> Bool {
        unit == KeyboardSizing.defaultUnit && offset == KeyboardSizing.defaultOffset
    }

    static func isDefault(in defaults: UserDefaults) -> Bool {
        isDefault(unit: defaults.object(forKey: SettingsKey.keyboardUnit) as? Double ?? KeyboardSizing.defaultUnit,
                  offset: defaults.object(forKey: SettingsKey.keyboardOffset) as? Double ?? KeyboardSizing.defaultOffset)
    }

    static func reset(in defaults: UserDefaults) {
        defaults.set(KeyboardSizing.defaultUnit, forKey: SettingsKey.keyboardUnit)
        defaults.set(KeyboardSizing.defaultOffset, forKey: SettingsKey.keyboardOffset)
    }
}
