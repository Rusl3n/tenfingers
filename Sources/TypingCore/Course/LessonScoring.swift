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

    /// Звёзды урока из истории: лучшая завершённая проверка урока (`exerciseKind == .check`) по её скорости
    /// и точности. `nil`, если проверок в истории нет.
    public static func bestStars(sessions: [SessionSummary], lessonId: String, targetCpm: Int) -> Int? {
        sessions
            .filter { $0.completed && $0.lessonId == lessonId && $0.exerciseKind == .check }
            .map { stars(cpm: $0.speed, accuracy: $0.accuracy, targetCpm: targetCpm) }
            .max()
    }
}
