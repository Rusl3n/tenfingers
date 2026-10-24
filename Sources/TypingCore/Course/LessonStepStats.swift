/// Итог шага урока по всем завершённым попыткам.
public struct StepStat: Equatable, Sendable {
    public let kind: ExerciseKind
    /// Лучшая точность.
    public let bestAccuracy: Double
    /// Ошибок в лучшей (самой точной, при равенстве — самой быстрой) попытке.
    public let errorsInBest: Int
    /// Скорость лучшей попытки: с ней сравнивается новая попытка той же точности.
    public let cpmInBest: Double
    /// Лучшая скорость (знаков в минуту) среди всех попыток (показывается на карте курса).
    public let bestCpm: Double

    public init(kind: ExerciseKind, bestAccuracy: Double, errorsInBest: Int, cpmInBest: Double, bestCpm: Double) {
        self.kind = kind
        self.bestAccuracy = bestAccuracy
        self.errorsInBest = errorsInBest
        self.cpmInBest = cpmInBest
        self.bestCpm = bestCpm
    }
}

/// Детали урока по шагам (`exerciseKind`) из истории сессий.
public enum LessonStepStats {
    /// Шаги урока с завершёнными попытками, в порядке урока (отработка → сочетания → слова → проверка).
    public static func summarize(sessions: [SessionSummary], lessonId: String) -> [StepStat] {
        let attempts = sessions.filter { $0.completed && $0.lessonId == lessonId && $0.exerciseKind != nil }
        let byKind = Dictionary(grouping: attempts) { $0.exerciseKind! }
        return ExerciseKind.allCases.compactMap { kind in
            guard let list = byKind[kind],
                  let best = list.max(by: { ($0.accuracy, $0.speed) < ($1.accuracy, $1.speed) }) else { return nil }
            return StepStat(kind: kind, bestAccuracy: best.accuracy, errorsInBest: best.errorCount,
                            cpmInBest: best.speed, bestCpm: list.map(\.speed).max() ?? 0)
        }
    }

    /// Сумма ошибок лучших попыток шагов (строка урока на карте курса); `nil`, если шагов нет.
    public static func totalErrors(_ steps: [StepStat]) -> Int? {
        guard !steps.isEmpty else { return nil }
        return steps.reduce(0) { $0 + $1.errorsInBest }
    }

    /// Новая попытка лучше прежней лучшей: точнее, а при той же точности — быстрее её же.
    /// Первая попытка всегда лучшая.
    public static func isImprovement(accuracy: Double, cpm: Double, over previous: StepStat?) -> Bool {
        guard let previous else { return true }
        return accuracy > previous.bestAccuracy || (accuracy == previous.bestAccuracy && cpm > previous.cpmInBest)
    }
}
