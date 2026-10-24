public enum LessonScoring {
    /// Урок засчитан (★) от этой точности.
    public static let passAccuracy = 0.96
    /// ★★ — не медленнее цели и точность от 98%.
    public static let twoStarAccuracy = 0.98
    /// ★★★ — скорость от цели × 1,3 и точность от 99,5%.
    public static let threeStarFactor = 1.3
    public static let threeStarAccuracy = 0.995

    /// 0 — урок не засчитан; 1–3 — звёзды по скорости относительно цели и точности.
    public static func stars(cpm: Double, accuracy: Double, targetCpm: Int) -> Int {
        guard accuracy >= passAccuracy else { return 0 }
        let target = Double(targetCpm)
        if cpm >= target * threeStarFactor && accuracy >= threeStarAccuracy { return 3 }
        if cpm >= target && accuracy >= twoStarAccuracy { return 2 }
        return 1
    }

    /// Что нужно до следующей звезды: скорость (`needCpm`) и/или точность (`needAccuracy`), которых не хватает;
    /// уже выполненное условие — `nil`. Сама подсказка `nil`, если урок не засчитан или звёзд уже три.
    public static func nextStarHint(cpm: Double, accuracy: Double,
                                    targetCpm: Int) -> (needCpm: Double?, needAccuracy: Double?)? {
        let target = Double(targetCpm)
        let needCpm: Double, needAccuracy: Double
        switch stars(cpm: cpm, accuracy: accuracy, targetCpm: targetCpm) {
        case 1: (needCpm, needAccuracy) = (target, twoStarAccuracy)
        case 2: (needCpm, needAccuracy) = (target * threeStarFactor, threeStarAccuracy)
        default: return nil
        }
        return (cpm >= needCpm ? nil : needCpm, accuracy >= needAccuracy ? nil : needAccuracy)
    }

    /// «Действующая» оценка урока — единственное правило, по которому звёзды показывают карта курса и аналитика
    /// и считают ачивки (`LessonProgress.bestStars` напрямую не читать).
    /// По истории проверок (скорость и точность каждой завершённой проверки урока) — по текущему правилу;
    /// истории нет — `storedStars` из базы. У засчитанного урока (`passed`) — не меньше одной звезды:
    /// урок мог быть пройден до того, как шаги стали записываться, а неудачная проверка после этого
    /// не отменяет зачёта.
    public static func effectiveStars(history: [(cpm: Double, accuracy: Double)], targetCpm: Int, passed: Bool,
                                      storedStars: Int) -> Int {
        let base = history.map { stars(cpm: $0.cpm, accuracy: $0.accuracy, targetCpm: targetCpm) }.max() ?? storedStars
        return passed ? max(base, 1) : base
    }

    /// То же по сессиям: в историю идут завершённые проверки (`exerciseKind == .check`) этого урока.
    public static func effectiveStars(sessions: [SessionSummary], lessonId: String, targetCpm: Int, passed: Bool,
                                      storedStars: Int) -> Int {
        let history = sessions
            .filter { $0.completed && $0.lessonId == lessonId && $0.exerciseKind == .check }
            .map { (cpm: $0.speed, accuracy: $0.accuracy) }
        return effectiveStars(history: history, targetCpm: targetCpm, passed: passed, storedStars: storedStars)
    }
}
