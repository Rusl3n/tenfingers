import TypingCore

/// Что карта курса показывает об уроке: звёзды, шаги с лучшими попытками и средняя точность.
/// Звёзды пересчитываются из истории по текущему правилу; `LessonProgress.bestStars` в базе не меняется.
struct LessonOverview: Equatable {
    let stars: Int
    let steps: [StepStat]

    var averageAccuracy: Double? { LessonStepStats.averageAccuracy(steps) }

    /// Звёзды — `LessonScoring.effectiveStars`: `storedStars` (из базы) нужны, только если в истории нет ни одной
    /// проверки урока, а у пройденного урока (`isPassed`) их не меньше одной.
    static func make(lessonId: String, targetCpm: Int, sessions: [SessionSummary], storedStars: Int,
                     isPassed: Bool = false) -> LessonOverview {
        LessonOverview(stars: LessonScoring.effectiveStars(sessions: sessions, lessonId: lessonId, targetCpm: targetCpm,
                                                           passed: isPassed, storedStars: storedStars),
                       steps: LessonStepStats.summarize(sessions: sessions, lessonId: lessonId))
    }
}
