import Foundation

/// Куда тянуться пальцу от исходной клавиши: «вверх и вправо» и т. п. Текст — на языке системы.
public enum ReachDescription {
    static let home = "исходная позиция"
    static let inPlace = "на месте"
    static let up = "вверх"
    static let down = "вниз"
    static let left = "влево"
    static let right = "вправо"
    static let rowsUp = "на %lld ряда вверх"
    static let rowsDown = "на %lld ряда вниз"
    static let joiner = " и "
    /// Все ключи перевода фрагментов.
    static let keys = [home, inPlace, up, down, left, right, rowsUp, rowsDown, joiner]

    public static func describe(keyCode: UInt16, shape: KeyboardShape) -> String {
        describe(keyCode: keyCode, shape: shape, localization: nil)
    }

    /// `localization` — язык перевода (`"ru"`, `"en"`); `nil` — язык системы.
    static func describe(keyCode: UInt16, shape: KeyboardShape, localization: String?) -> String {
        func text(_ key: String) -> String { CoreText.localized(key, localization: localization) }
        guard let finger = FingerMap.finger(for: keyCode) else { return "" }
        let homeCode = finger.homeKeyCode
        if homeCode == keyCode { return text(home) }
        guard let from = KeyboardGeometry.position(of: homeCode, shape: shape),
              let to = KeyboardGeometry.position(of: keyCode, shape: shape) else { return "" }

        var parts: [String] = []
        let rows = to.row - from.row
        switch rows {
        case ..<(-1): parts.append(String(format: text(rowsUp), -rows))
        case -1: parts.append(text(up))
        case 1: parts.append(text(down))
        case 2...: parts.append(String(format: text(rowsDown), rows))
        default: break
        }
        let dx = to.x - from.x
        if dx < -0.6 { parts.append(text(left)) } else if dx > 0.6 { parts.append(text(right)) }
        return parts.isEmpty ? text(inPlace) : parts.joined(separator: text(joiner))
    }
}
