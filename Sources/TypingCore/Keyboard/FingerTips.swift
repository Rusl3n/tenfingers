import Foundation

/// Точка на плоскости клавиатуры (в единицах приложения, без CoreGraphics).
public struct PlanePoint: Equatable, Sendable {
    public var x: Double
    public var y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }
}

/// Кончики пальцев: исходные точки, дуга нажатия и размер кружка.
public struct FingerTipsLayout: Sendable {
    private let homeKeys: [Finger: PlanePoint]
    /// Кончики больших пальцев над пробелом (на ⅓ и ⅔ его ширины).
    public let thumbs: (left: PlanePoint, right: PlanePoint)
    private let keyPitch: Double
    private let keyboardCenterX: Double

    public init(
        homeKeys: [Finger: PlanePoint],
        space: (left: PlanePoint, right: PlanePoint),
        keyPitch: Double,
        keyboardCenterX: Double
    ) {
        self.homeKeys = homeKeys
        self.thumbs = space
        self.keyPitch = keyPitch
        self.keyboardCenterX = keyboardCenterX
    }

    /// Центр основной клавиши пальца; для большого — правая точка над пробелом.
    public func home(_ finger: Finger) -> PlanePoint {
        finger == .thumb ? thumbs.right : (homeKeys[finger] ?? thumbs.right)
    }

    /// Начало, контрольная точка и конец дуги. Контрольная точка — середина отрезка,
    /// сдвинутая по x на ⅓ шага клавиш наружу от центра клавиатуры.
    public func arc(finger: Finger, to target: PlanePoint) -> (start: PlanePoint, control: PlanePoint, end: PlanePoint) {
        let start = home(finger)
        if start == target { return (start, start, target) }
        let side: Double = start.x < keyboardCenterX ? -1 : 1
        let control = PlanePoint(
            x: (start.x + target.x) / 2 + side * keyPitch / 3,
            y: (start.y + target.y) / 2
        )
        return (start, control, target)
    }

    /// Точка квадратичной кривой Безье; progress зажат в 0…1.
    public func position(finger: Finger, target: PlanePoint, progress: Double) -> PlanePoint {
        let t = min(max(progress, 0), 1)
        let (p0, p1, p2) = arc(finger: finger, to: target)
        let a = (1 - t) * (1 - t), b = 2 * (1 - t) * t, c = t * t
        return PlanePoint(x: a * p0.x + b * p1.x + c * p2.x, y: a * p0.y + b * p1.y + c * p2.y)
    }

    /// Диаметр кружка: 0,4 шага в покое, 0,5 при нажатии.
    public func diameter(pressing: Bool) -> Double { keyPitch * (pressing ? 0.5 : 0.4) }
}

/// Тайминг нажатия: 170 мс вниз, 160 мс на клавише, 190 мс назад. При быстром темпе те же доли сжимаются
/// до `durationMs`, заданного функцией `duration(forIntervalMs:)`.
public enum FingerPress {
    public static let durationMs = 520.0
    /// Короче нажатие не рисуем: движение перестало бы быть видно.
    public static let minDurationMs = 100.0

    /// Длительность анимации нажатия, если до следующего нажатия `intervalMs` (`nil` — следующего нет).
    public static func duration(forIntervalMs intervalMs: Double?) -> Double {
        guard let intervalMs else { return durationMs }
        return min(durationMs, max(minDurationMs, intervalMs * 0.9))
    }

    public static func progress(elapsedMs: Double) -> Double {
        switch elapsedMs {
        case ..<0: 0
        case ..<170: elapsedMs / 170
        case ..<330: 1
        case ..<durationMs: 1 - (elapsedMs - 330) / 190
        default: 0
        }
    }

    /// То же при сжатой длительности `durationMs`: время приводится к шкале 520 мс.
    public static func progress(elapsedMs: Double, durationMs total: Double) -> Double {
        progress(elapsedMs: elapsedMs * scale(total))
    }

    /// Клавиша подсвечена как нажатая.
    public static func isDown(elapsedMs: Double) -> Bool { elapsedMs >= 140 && elapsedMs <= 360 }

    public static func isDown(elapsedMs: Double, durationMs total: Double) -> Bool {
        isDown(elapsedMs: elapsedMs * scale(total))
    }

    private static func scale(_ total: Double) -> Double { durationMs / max(total, 1) }
}
