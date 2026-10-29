/// Итог шага урока по всем завершённым попыткам.
public struct StepStat: Hashable, Sendable {
    public let kind: ExerciseKind
    /// Лучшая точность.
    public let bestAccuracy: Double
    /// Ошибок в лучшей (самой точной, при равенстве — самой быстрой) попытке.
    public let errorsInBest: Int
    /// Скорость лучшей попытки: с ней сравнивается новая попытка той же точности.
    public let cpmInBest: Double
    /// Лучшая скорость (знаков в минуту) среди всех попыток (показывается на карте курса).
    public let bestCpm: Double
    /// Номер шага в плане урока; `nil` — только записи без номера (до 6a), группа по виду.
    public let stepIndex: Int?

    public init(kind: ExerciseKind, bestAccuracy: Double, errorsInBest: Int, cpmInBest: Double, bestCpm: Double,
                stepIndex: Int? = nil) {
        self.kind = kind
        self.bestAccuracy = bestAccuracy
        self.errorsInBest = errorsInBest
        self.cpmInBest = cpmInBest
        self.bestCpm = bestCpm
        self.stepIndex = stepIndex
    }
}

/// Детали урока по шагам из истории сессий: по номеру шага (`stepIndex`), записи без номера — по виду (решение 22).
public enum LessonStepStats {
    /// Шаги урока с завершёнными попытками, в порядке урока. Группы — по (номер, вид): в уроках издания 2 виды
    /// повторяются. Запись без номера (до 6a) идёт в первый по номеру шаг того же вида, а если его нет — в группу
    /// по виду на прежнем месте вида (отработка → сочетания → слова → проверка, прочие — после них).
    public static func summarize(sessions: [SessionSummary], lessonId: String) -> [StepStat] {
        let attempts = sessions.filter { $0.completed && $0.lessonId == lessonId && $0.exerciseKind != nil }
        let numbered = attempts.filter { $0.stepIndex != nil }
        // Первый по номеру шаг каждого вида.
        var firstIndex: [ExerciseKind: Int] = [:]
        for attempt in numbered {
            let kind = attempt.exerciseKind!, index = attempt.stepIndex!
            firstIndex[kind] = min(firstIndex[kind] ?? index, index)
        }
        let groups = Dictionary(grouping: attempts) { attempt in
            GroupKey(index: attempt.stepIndex ?? firstIndex[attempt.exerciseKind!], kind: attempt.exerciseKind!)
        }
        return groups.sorted { lhs, rhs in
            let l = lhs.key.index ?? kindRank(lhs.key.kind), r = rhs.key.index ?? kindRank(rhs.key.kind)
            if l != r { return l < r }
            if (lhs.key.index == nil) != (rhs.key.index == nil) { return lhs.key.index != nil }
            return kindRank(lhs.key.kind) < kindRank(rhs.key.kind)
        }.compactMap { key, list in
            guard let best = list.max(by: { ($0.accuracy, $0.speed) < ($1.accuracy, $1.speed) }) else { return nil }
            return StepStat(kind: key.kind, bestAccuracy: best.accuracy, errorsInBest: best.errorCount,
                            cpmInBest: best.speed, bestCpm: list.map(\.speed).max() ?? 0, stepIndex: key.index)
        }
    }

    private struct GroupKey: Hashable {
        let index: Int?
        let kind: ExerciseKind
    }

    /// Место вида у групп без номера: прежний порядок шагов (drill 0, combos 1, words 2, check 3),
    /// новые виды — 100 + индекс в `allCases`.
    static func kindRank(_ kind: ExerciseKind) -> Int {
        switch kind {
        case .drill: 0
        case .combos: 1
        case .words: 2
        case .check: 3
        default: 100 + (ExerciseKind.allCases.firstIndex(of: kind) ?? 0)
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
