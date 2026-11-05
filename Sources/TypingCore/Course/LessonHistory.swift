import Foundation

// Статистика урока с прогрессией (фаза 8a, задача 6b): проходы-проверки и рост скорости по шагам.

/// Проход урока: завершённая проверка (`check` или «Освежить»).
public struct LessonCheckPass: Equatable, Sendable {
    public let date: Date
    public let cpm: Double
    public let errors: Int
    public let stars: Int

    public init(date: Date, cpm: Double, errors: Int, stars: Int) {
        self.date = date
        self.cpm = cpm
        self.errors = errors
        self.stars = stars
    }
}

/// Скорость шага от первой до последней записи. `stepIndex == nil` — архивные записи без номера (группа по виду).
public struct LessonStepProgress: Equatable, Sendable {
    public let stepIndex: Int?
    public let kind: ExerciseKind
    public let runs: Int
    public let first: Double
    public let last: Double
    /// Изменение скорости в процентах; у шага с одной записью — `nil`.
    public let changePercent: Int?
}

public struct LessonHistoryStats: Equatable, Sendable {
    /// Проходы по времени, старые первыми.
    public let passes: [LessonCheckPass]
    public let steps: [LessonStepProgress]
    public init(passes: [LessonCheckPass], steps: [LessonStepProgress]) {
        self.passes = passes
        self.steps = steps
    }

    public var firstDate: Date? { passes.first?.date }
    public var lastDate: Date? { passes.last?.date }
}

public enum LessonHistory {
    public static func make(lessonId: String, sessions: [SessionSummary], targetCpm: Int) -> LessonHistoryStats {
        let own = sessions
            .filter { $0.completed && $0.mode == .course && $0.lessonId == lessonId }
            .sorted { $0.endedAt < $1.endedAt }
        let passes = own
            .filter { $0.exerciseKind?.isLessonCheck ?? false }
            .map { LessonCheckPass(date: $0.endedAt, cpm: $0.speed, errors: $0.errorCount,
                              stars: LessonScoring.stars(cpm: $0.speed, accuracy: $0.accuracy, targetCpm: targetCpm)) }
        var order: [String] = []
        var groups: [String: [SessionSummary]] = [:]
        for session in own {
            guard let kind = session.exerciseKind, !kind.isLessonCheck else { continue }
            let key = session.stepIndex.map { "i\($0)" } ?? "k\(kind.rawValue)"
            if groups[key] == nil { order.append(key) }
            groups[key, default: []].append(session)
        }
        let steps = order.compactMap { key -> LessonStepProgress? in
            guard let runs = groups[key], let first = runs.first, let last = runs.last, let kind = last.exerciseKind
            else { return nil }
            var change: Int?
            if runs.count > 1, first.speed > 0 {
                change = Int(((last.speed - first.speed) / first.speed * 100).rounded())
            }
            return LessonStepProgress(stepIndex: first.stepIndex, kind: kind, runs: runs.count,
                                      first: first.speed, last: last.speed, changePercent: change)
        }
        // Шаги с номером — по номеру, архивные без номера — после, в порядке появления.
        let numbered = steps.filter { $0.stepIndex != nil }.sorted { ($0.stepIndex ?? 0) < ($1.stepIndex ?? 0) }
        return LessonHistoryStats(passes: passes, steps: numbered + steps.filter { $0.stepIndex == nil })
    }
}
