import CoreGraphics
import Foundation

/// Масштаб интерфейса (настройка «Масштаб интерфейса»): содержимое окна размечается в «логических» точках
/// (размер области, делённый на масштаб) и увеличивается или уменьшается целиком, как зум в браузере.
enum UIScale {
    static let options: [Double] = [0.8, 0.9, 1.0, 1.1, 1.25, 1.5]
    static let defaultValue = 1.0
    /// Обычный минимальный размер окна (при масштабе 100% и меньше).
    static let baseMinimumWindowSize = CGSize(width: 960, height: 640)

    /// Ближайшее допустимое значение из `options`; нечисло и бесконечность — 100%.
    static func clamped(_ value: Double) -> Double {
        guard value.isFinite else { return defaultValue }
        return options.min { abs($0 - value) < abs($1 - value) } ?? defaultValue
    }

    /// «125%».
    static func title(_ scale: Double) -> String { "\(Int((scale * 100).rounded()))%" }

    /// Размер, под который размечается содержимое, чтобы после увеличения в `scale` раз занять `size`.
    static func logicalSize(_ size: CGSize, scale: Double) -> CGSize {
        let scale = CGFloat(clamped(scale))
        return CGSize(width: size.width / scale, height: size.height / scale)
    }

    /// Минимальный размер окна: при масштабе больше 100% растёт вместе с ним, но не больше видимой области экрана
    /// (и не меньше обычного минимума).
    static func minimumWindowSize(scale: Double, visible: CGSize?) -> CGSize {
        let base = baseMinimumWindowSize
        let scale = CGFloat(max(clamped(scale), 1))
        var size = CGSize(width: base.width * scale, height: base.height * scale)
        if let visible {
            size.width = max(base.width, min(size.width, visible.width))
            size.height = max(base.height, min(size.height, visible.height))
        }
        return size
    }
}
