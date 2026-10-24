/// Порог звезды выше первой: скорость от `speedFactor` × цели урока и точность от `accuracy`.
public struct StarThreshold: Equatable, Sendable {
    public let stars: Int
    public let speedFactor: Double
    public let accuracy: Double
}

/// Чего не хватает до следующей звезды: скорости (`needCpm`) и/или ошибок (`maxErrors` — сколько их можно
/// на этом тексте); для ★★★★★ ещё и чистого шага урока (`blockingStep`). Выполненное условие — `nil`.
public struct NextStarHint: Equatable, Sendable {
    public let stars: Int
    public let needCpm: Double?
    public let maxErrors: Int?
    /// Шаг урока (не проверка), лучшая попытка которого хуже порога чистого урока; только у подсказки к ★★★★★.
    public let blockingStep: ExerciseKind?

    public init(stars: Int, needCpm: Double?, maxErrors: Int?, blockingStep: ExerciseKind? = nil) {
        self.stars = stars
        self.needCpm = needCpm
        self.maxErrors = maxErrors
        self.blockingStep = blockingStep
    }
}

public enum LessonScoring {
    /// Звёзд у урока не больше пяти (спецификация фазы 6, §4).
    public static let maxStars = 5
    /// Урок засчитан (★) от этой точности: не больше 4 ошибок на 100 знаков.
    public static let passAccuracy = 0.96
    /// Точность ★★★ (и ★★★★ — прежняя 98% лежит между ними): ниже неё результат шага на карте курса подсвечен.
    public static let threeStarAccuracy = 0.98
    /// ★★…★★★★★ по возрастанию. Шкала монотонна и содержит прежнюю: прежние ★★ (цель, 98%) — это ★★★,
    /// прежние ★★★ (×1,3, 99,5%) — ★★★★.
    public static let thresholds: [StarThreshold] = [
        StarThreshold(stars: 2, speedFactor: 0.8, accuracy: 0.97),
        StarThreshold(stars: 3, speedFactor: 1.0, accuracy: threeStarAccuracy),
        StarThreshold(stars: 4, speedFactor: 1.3, accuracy: 0.995),
        StarThreshold(stars: 5, speedFactor: 1.5, accuracy: 1.0),
    ]
    /// ★★★★★ — только за чистый урок: у каждого шага, кроме проверки, лучшая попытка не больше 2 ошибок
    /// на 100 знаков (точность от этой). Порог в тексте — через `allowedErrors`, без процентов.
    public static let cleanLessonStepAccuracy = 0.98
    /// «Отличник курса» (`course.stars.*`): все уроки не ниже этого — прежний максимум ★★★.
    public static let excellentStars = 4
    /// Допуск сравнения точности: 1 − 1/200 в двоичной арифметике может оказаться чуть меньше 0,995.
    public static let accuracyTolerance = 1e-9

    public static func threshold(for stars: Int) -> StarThreshold? { thresholds.first { $0.stars == stars } }

    /// 0 — урок не засчитан; 1–5 — по скорости относительно цели и точности.
    public static func stars(cpm: Double, accuracy: Double, targetCpm: Int) -> Int {
        guard accuracy + accuracyTolerance >= passAccuracy else { return 0 }
        let target = Double(targetCpm)
        return thresholds.last {
            cpm >= target * $0.speedFactor && accuracy + accuracyTolerance >= $0.accuracy
        }?.stars ?? 1
    }

    /// Сколько ошибок допускает точность на тексте из `chars` знаков: floor(n · (1 − точность) + допуск).
    public static func allowedErrors(chars: Int, accuracy: Double) -> Int {
        max(0, Int((Double(chars) * (1 - accuracy) + accuracyTolerance).rounded(.down)))
    }

    /// Шаги урока (кроме проверки) без чистой лучшей попытки, в порядке урока. Шаг без завершённых попыток
    /// в `steps` не входит (`LessonStepStats.summarize`), поэтому не мешает: урок мог быть пройден до того,
    /// как шаги стали записываться.
    public static func uncleanSteps(_ steps: [StepStat]) -> [ExerciseKind] {
        steps.filter { $0.kind != .check && $0.bestAccuracy + accuracyTolerance < cleanLessonStepAccuracy }
            .map(\.kind)
    }

    /// Звёзды урока по звёздам проверки `checkStars` и шагам урока: пятая — только если все шаги чистые,
    /// иначе четыре. Ниже пятой шаги на звёзды не влияют.
    public static func lessonStars(checkStars: Int, steps: [StepStat]) -> Int {
        checkStars >= maxStars && !uncleanSteps(steps).isEmpty ? maxStars - 1 : checkStars
    }

    /// Подсказка до следующей звезды по результату проверки (`errors` ошибок на `chars` знаках) и шагам урока.
    /// К ★★★★★ она называет и мешающий шаг. `nil` — урок не засчитан, звёзд уже пять или всех условий хватает.
    public static func nextStarHint(cpm: Double, accuracy: Double, errors: Int, chars: Int, targetCpm: Int,
                                    steps: [StepStat]) -> NextStarHint? {
        let current = stars(cpm: cpm, accuracy: accuracy, targetCpm: targetCpm)
        guard current >= 1 else { return nil }
        let blocking = uncleanSteps(steps).first
        // Проверка уже на пятёрку: мешать может только шаг.
        guard let next = threshold(for: current + 1) else {
            return blocking.map { NextStarHint(stars: maxStars, needCpm: nil, maxErrors: nil, blockingStep: $0) }
        }
        let needCpm = Double(targetCpm) * next.speedFactor
        let allowed = allowedErrors(chars: chars, accuracy: next.accuracy)
        let hint = NextStarHint(stars: next.stars, needCpm: cpm >= needCpm ? nil : needCpm,
                                maxErrors: errors <= allowed ? nil : allowed,
                                blockingStep: next.stars == maxStars ? blocking : nil)
        return hint.needCpm == nil && hint.maxErrors == nil && hint.blockingStep == nil ? nil : hint
    }

    /// Прежняя шкала (хранится в `LessonProgress.bestStars` уроков издания 1) → новая: 1 → ★, 2 → ★★★, 3 → ★★★★.
    public static func fiveStarScale(legacy stars: Int) -> Int {
        switch stars {
        case ...0: 0
        case 1: 1
        case 2: 3
        default: 4
        }
    }

    /// Новая шкала → прежняя, для записи в `bestStars` уроков издания 1: 1–2 → 1, 3 → 2, 4–5 → 3.
    public static func legacyScale(fiveStar stars: Int) -> Int {
        switch stars {
        case ...0: 0
        case 1, 2: 1
        case 3: 2
        default: 3
        }
    }

    /// «Действующая» оценка урока — единственное правило, по которому звёзды показывают карта курса и аналитика
    /// и считают ачивки (`LessonProgress.bestStars` напрямую не читать).
    /// По истории проверок (скорость и точность каждой завершённой проверки урока) — по текущему правилу,
    /// а пятая звезда ещё и по шагам урока (`steps` — `LessonStepStats.summarize`, `lessonStars`);
    /// истории нет — `storedStars` из базы. У засчитанного урока (`passed`) — не меньше одной звезды:
    /// урок мог быть пройден до того, как шаги стали записываться, а неудачная проверка после этого
    /// не отменяет зачёта. `storedStars` — `LessonProgress.bestStars` в шкале издания 1; без истории он
    /// переводится в новую шкалу (`fiveStarScale`).
    public static func effectiveStars(history: [(cpm: Double, accuracy: Double)], steps: [StepStat], targetCpm: Int,
                                      passed: Bool, storedStars: Int) -> Int {
        let base = history.map { stars(cpm: $0.cpm, accuracy: $0.accuracy, targetCpm: targetCpm) }.max()
            .map { lessonStars(checkStars: $0, steps: steps) } ?? fiveStarScale(legacy: storedStars)
        return passed ? max(base, 1) : base
    }

    /// То же по сессиям: в историю идут завершённые проверки (`exerciseKind == .check`) этого урока, а шаги —
    /// лучшие попытки всех его шагов (`LessonStepStats`, те же, что в деталях урока на карте курса).
    public static func effectiveStars(sessions: [SessionSummary], lessonId: String, targetCpm: Int, passed: Bool,
                                      storedStars: Int) -> Int {
        let history = sessions
            .filter { $0.completed && $0.lessonId == lessonId && $0.exerciseKind == .check }
            .map { (cpm: $0.speed, accuracy: $0.accuracy) }
        return effectiveStars(history: history, steps: LessonStepStats.summarize(sessions: sessions, lessonId: lessonId),
                              targetCpm: targetCpm, passed: passed, storedStars: storedStars)
    }
}
