import Foundation

/// Ориентир урока «Ускорение» (§6.2, решение 16): с чем сравнивается скорость проверки и что показать на итоге.
public enum SpeedupReference {
    /// Цель обгона на экране — ориентир × 1,05, округление до 1 (§6.2).
    public static let overtakeFactor = 1.05
    /// Столько последних проверок курса усредняется, если «Ускорение» ещё не проходили.
    static let fallbackChecks = 5
    /// Допуск сравнения: ровно +5% из-за двоичной арифметики не становится +6%.
    private static let tolerance = 1e-9

    /// Ориентир «Ускорения» языка: лучшая скорость завершённой проверки (`check`) уроков `speedup` курса;
    /// нет — средняя скорость последних 5 завершённых проверок курса (`mode == .course`, `check`, любое издание);
    /// `nil` — проверок нет. `sessions` — сессии этого языка.
    public static func reference(course: Course, sessions: [SessionSummary]) -> Double? {
        let checks = sessions.filter { $0.mode == .course && $0.completed && $0.exerciseKind == .check }
        let speedupIds = Set(course.lessons.filter { $0.resolvedKind == .speedup }.map(\.id))
        if let best = checks.filter({ speedupIds.contains($0.lessonId ?? "") }).map(\.speed).max() { return best }
        let recent = checks.sorted { $0.endedAt < $1.endedAt }.suffix(fallbackChecks)
        guard !recent.isEmpty else { return nil }
        return recent.reduce(0) { $0 + $1.speed } / Double(recent.count)
    }

    public static func goal(reference: Double) -> Int {
        Int((reference * overtakeFactor).rounded())
    }

    public enum Outcome: Equatable, Sendable {
        /// «Рекорд побит: +N%» (N ≥ 1).
        case beaten(percent: Int)
        /// «До рекорда не хватило M» (M ≥ 1, зн/мин).
        case short(cpm: Int)
    }

    /// Выше ориентира — N = ⌈(скорость / ориентир − 1) · 100⌉; иначе M = max(1, ⌈ориентир − скорость⌉) (решение 16).
    public static func outcome(cpm: Double, reference: Double) -> Outcome {
        if cpm > reference, reference > 0 {
            let percent = ((cpm - reference) / reference * 100 - tolerance).rounded(.up)
            return .beaten(percent: max(1, Int(percent)))
        }
        return .short(cpm: max(1, Int((reference - cpm - tolerance).rounded(.up))))
    }
}
