import Foundation

/// «Сертификат» за пройденный курс издания 2 (спецификация фазы 6, §16, решение 18).
public enum Certificate {
    /// Средняя скорость проверок этапов (знаков в минуту), с которой курс даёт сертификат.
    public static let minimumAverageCpm = 120.0

    /// Средняя по этапам скорость лучших завершённых проверок этапа, взявших порог (`Stage.gate`); `nil` — не у всех
    /// этапов есть такая проверка (или у курса нет проверок этапов, как у издания 1).
    public static func averageCheckCpm(course: Course, sessions: [SessionSummary]) -> Double? {
        var speeds: [Double] = []
        for stage in course.stages {
            guard let check = stage.checkLesson else { return nil }
            let best = CourseGate.scoredChecks(course: course, checkLessonId: check.id, sessions: sessions)
                .filter { $0.stars >= stage.gate }
                .map(\.speed)
                .max()
            guard let best else { return nil }
            speeds.append(best)
        }
        return speeds.isEmpty ? nil : speeds.reduce(0, +) / Double(speeds.count)
    }

    /// Курс издания 2 пройден и средняя не ниже `minimumAverageCpm` — средняя; иначе `nil`.
    public static func eligibleAverage(course: Course, passed: Set<String>, sessions: [SessionSummary]) -> Double? {
        guard course.edition >= 2,
              course.isCompleted(passed: passed, checkStars: CourseGate.checkStars(course: course, sessions: sessions)),
              let average = averageCheckCpm(course: course, sessions: sessions),
              average >= minimumAverageCpm else { return nil }
        return average
    }
}
