import TypingCore

/// Что карта курса показывает об уроке: звёзды, шаги с лучшими попытками и средняя точность.
/// Звёзды пересчитываются из истории по текущему правилу; `LessonProgress.bestStars` в базе не меняется.
struct LessonOverview: Equatable {
    let stars: Int
    let steps: [StepStat]

    var averageAccuracy: Double? { LessonStepStats.averageAccuracy(steps) }

    /// `storedStars` (из базы) используется, только если в истории нет ни одной проверки урока.
    /// У пройденного урока (`isPassed`) — не меньше одной звезды: урок мог быть пройден до того, как шаги
    /// стали записываться, а неудачная проверка после этого не отменяет прохождения.
    static func make(lessonId: String, targetCpm: Int, sessions: [SessionSummary], storedStars: Int,
                     isPassed: Bool = false) -> LessonOverview {
        let stars = LessonScoring.bestStars(sessions: sessions, lessonId: lessonId, targetCpm: targetCpm) ?? storedStars
        return LessonOverview(stars: isPassed ? max(stars, 1) : stars,
                              steps: LessonStepStats.summarize(sessions: sessions, lessonId: lessonId))
    }
}
