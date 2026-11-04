import Foundation

public enum RhythmMissReason: Equatable, Sendable {
    case skipped
    case wrongKey(pressed: Character)
}

public enum RhythmJudgement: Equatable, Sendable {
    case perfect, good, early, late
    case miss(RhythmMissReason)

    public var isHit: Bool {
        if case .miss = self { return false }
        return true
    }

    /// Базовые очки до множителя.
    public var points: Int {
        switch self {
        case .perfect: 300
        case .good: 200
        case .early, .late: 100
        case .miss: 0
        }
    }
}

/// Окна оценки (§3.4), границы включительно.
public enum RhythmJudge {
    public static let perfectWindow: TimeInterval = 0.070
    public static let goodWindow: TimeInterval = 0.130
    public static let hitWindow: TimeInterval = 0.200
    /// Допуск на погрешность `Double` при сравнении с границами окон.
    static let epsilon: TimeInterval = 1e-9

    /// Оценка по отклонению (нажатие − нота); `nil` — вне окна. Отрицательное отклонение — рано.
    /// `scale` — множитель окон ноты (`RhythmNote.windowScale`).
    public static func timing(offset: TimeInterval, scale: Double = 1) -> RhythmJudgement? {
        let distance = abs(offset)
        if distance <= perfectWindow * scale + epsilon { return .perfect }
        if distance <= goodWindow * scale + epsilon { return .good }
        if distance <= hitWindow * scale + epsilon { return offset < 0 ? .early : .late }
        return nil
    }
}
