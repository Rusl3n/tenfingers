import Foundation
import TypingCore

/// Порог проверки этапа на экране итога (спецификация фазы 6, §3; решение 15) и «Следующий урок» по гейту.
enum GateHint {
    /// «Чтобы открыть этап 3, нужно ★★★: не медленнее 110 зн/мин и не больше 2 ошибок на 100 знаков»;
    /// у последнего этапа — «Чтобы пройти курс, нужно …». `checkStars` — звёзды этой попытки проверки.
    /// `nil` — урок не проверка этапа издания 2, порог взят или урок не засчитан.
    static func text(course: Course, lessonId: String, checkStars: Int, unit: SpeedUnit) -> String? {
        guard course.edition >= 2, checkStars >= 1,
              let index = course.stages.firstIndex(where: { $0.checkLesson?.id == lessonId }) else { return nil }
        let stage = course.stages[index]
        guard checkStars < stage.gate, let threshold = LessonScoring.threshold(for: stage.gate),
              let target = course.targetCpm(for: lessonId) else { return nil }
        let stars = String(repeating: "★", count: stage.gate)
        let speed = StarHintText.speedGoal(targetCpm: target, factor: threshold.speedFactor, unit: unit)
        let errors = StarHintText.errorsRule(accuracy: threshold.accuracy)
        if index == course.stages.count - 1 {
            return String(localized: "Чтобы пройти курс, нужно \(stars): не медленнее \(speed) и \(errors)")
        }
        let opens = index + 2
        return String(localized: "Чтобы открыть этап \(opens), нужно \(stars): не медленнее \(speed) и \(errors)")
    }

    /// Строка порога на итоге проверки: по лучшим звёздам, а не только по этой попытке. `attemptStars` — звёзды этой
    /// попытки (0 — не проверка или не засчитана), `storedCheckStars` — звёзды проверок по истории (с этой попыткой
    /// или без неё). Порог уже взят раньше — `nil`, слабая пересдача его не отменяет.
    static func text(course: Course, lessonId: String, attemptStars: Int, storedCheckStars: [String: Int],
                     unit: SpeedUnit) -> String? {
        guard attemptStars > 0 else { return nil }
        let best = max(attemptStars, storedCheckStars[lessonId] ?? 0)
        return text(course: course, lessonId: lessonId, checkStars: best, unit: unit)
    }

    /// Последний «Повтор» этапа проверки (решение 15); у этапа без «Повтора» — `nil`: кнопки нет.
    static func reviewLesson(course: Course, checkLessonId: String) -> Lesson? {
        course.stages.first { $0.checkLesson?.id == checkLessonId }?
            .lessons.last { $0.resolvedKind == .review }
    }

    /// Следующий урок курса, если он открыт по гейту с учётом этой попытки: `stars` — звёзды урока (0 — не засчитан),
    /// `passed` и `checkStars` — прогресс до неё. Проверка ниже порога не ведёт в закрытый этап.
    static func nextLesson(course: Course, after lessonId: String, stars: Int, passed: Set<String>,
                           checkStars: [String: Int]) -> Lesson? {
        let lessons = course.lessons
        guard stars > 0, let index = lessons.firstIndex(where: { $0.id == lessonId }),
              index + 1 < lessons.count else { return nil }
        let next = lessons[index + 1]
        let attempt = CourseGate.withAttempt(course: course, lessonId: lessonId, stars: stars, passed: passed,
                                             checkStars: checkStars)
        return course.isUnlocked(next.id, passed: attempt.passed, checkStars: attempt.checkStars) ? next : nil
    }
}
