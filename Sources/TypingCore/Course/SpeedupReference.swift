import Foundation

/// Ориентир урока «Ускорение» (§6.2): от какой скорости считается цель и что показать на итоге проверки.
/// Ориентир — средняя скорость ученика, а не рекорд: одна удачная попытка не задирает цель всех следующих «Ускорений».
public enum SpeedupReference {
    /// Цель на экране — средняя × 1,10, округление до 1.
    public static let goalFactor = 1.10
    /// Столько последних завершённых шагов курса усредняется.
    static let recentSteps = 30
    /// Меньше шагов — средней нет, у «Ускорения» обычная цель урока.
    static let minimumSteps = 10
    /// Допуск сравнения: нехватка ровно в 7 зн/мин не становится 8 из-за двоичной арифметики.
    private static let tolerance = 1e-9

    /// Средняя скорость последних 30 завершённых шагов курса языка (`mode == .course`, любой вид шага, любое издание)
    /// без шагов уроков `speedup`: там сильные буквы и спринты, они быстрее обычных и тянули бы цель вверх.
    /// `nil` — таких шагов меньше 10. `sessions` — сессии этого языка.
    public static func reference(course: Course, sessions: [SessionSummary]) -> Double? {
        let speedupIds = Set(course.lessons.filter { $0.resolvedKind == .speedup }.map(\.id))
        let recent = sessions
            .filter { $0.mode == .course && $0.completed && $0.exerciseKind != nil
                && !speedupIds.contains($0.lessonId ?? "") }
            .sorted { $0.endedAt < $1.endedAt }
            .suffix(recentSteps)
        guard recent.count >= minimumSteps else { return nil }
        return recent.reduce(0) { $0 + $1.speed } / Double(recent.count)
    }

    public static func goal(reference: Double) -> Int {
        Int((reference * goalFactor).rounded())
    }

    public enum Outcome: Equatable, Sendable {
        /// «Цель взята».
        case reached
        /// «До цели не хватило M» (M ≥ 1, зн/мин).
        case short(cpm: Int)
    }

    /// Скорость проверки против цели: не ниже — взята; иначе M = max(1, ⌈цель − скорость⌉).
    public static func outcome(cpm: Double, goal: Int) -> Outcome {
        let gap = Double(goal) - cpm
        guard gap > tolerance else { return .reached }
        return .short(cpm: max(1, Int((gap - tolerance).rounded(.up))))
    }
}
