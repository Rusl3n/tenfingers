import TypingCore

/// Что карта курса показывает об уроке: звёзды, шаги с лучшими попытками и сумма ошибок лучших попыток шагов.
/// Звёзды пересчитываются из истории по текущему правилу; `LessonProgress.bestStars` в базе не меняется.
struct LessonOverview: Equatable {
    let stars: Int
    let steps: [StepStat]

    var errors: Int? { LessonStepStats.totalErrors(steps) }

    /// Скорость строки урока — лучшей (самой точной, затем самой быстрой) проверки урока, как в строке проверки
    /// среди шагов, а не самая высокая скорость проверок. Проверок в истории нет — `stored` (`LessonProgress.bestCpm`).
    func speed(stored: Double) -> Double {
        steps.last { $0.kind.isLessonCheck }?.cpmInBest ?? stored
    }

    /// Звёзды — `LessonScoring.effectiveStars`: `storedStars` (из базы) нужны, только если в истории нет ни одной
    /// проверки урока, а у пройденного урока (`isPassed`) их не меньше одной.
    static func make(lessonId: String, targetCpm: Int, sessions: [SessionSummary], storedStars: Int,
                     isPassed: Bool = false) -> LessonOverview {
        LessonOverview(stars: LessonScoring.effectiveStars(sessions: sessions, lessonId: lessonId, targetCpm: targetCpm,
                                                           passed: isPassed, storedStars: storedStars),
                       steps: LessonStepStats.summarize(sessions: sessions, lessonId: lessonId))
    }

    /// Звёзды урока после повтора шага, если стали больше (например, вернулась пятая); иначе `nil`.
    static func starsGained(before: Int, after: Int) -> Int? { after > before ? after : nil }
}
