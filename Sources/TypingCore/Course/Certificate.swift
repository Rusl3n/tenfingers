import Foundation

/// «Сертификат» за пройденный курс издания 2 (спецификация фазы 6, §16, решение 18).
public enum Certificate {
    /// Средняя скорость проверок этапов (знаков в минуту), с которой курс даёт сертификат.
    public static let minimumAverageCpm = 120.0

    /// Средняя по этапам скорость лучших завершённых проверок этапа, взявших порог (`Stage.gate`); `nil` — не у всех
    /// этапов есть такая проверка (или у курса нет проверок этапов, как у издания 1).
    public static func averageCheckCpm(course: Course, sessions: [SessionSummary]) -> Double? {
        let speeds = stageCheckSpeeds(course: course, sessions: sessions)
        return speeds.count == course.stages.count ? average(speeds) : nil
    }

    /// Средняя по уже сданным проверкам этапов (для показа прогресса); `nil` — ни одной сданной проверки.
    public static func passedChecksAverageCpm(course: Course, sessions: [SessionSummary]) -> Double? {
        average(stageCheckSpeeds(course: course, sessions: sessions))
    }

    /// Лучшая скорость проверки, взявшей порог, у каждого этапа, где такая есть.
    private static func stageCheckSpeeds(course: Course, sessions: [SessionSummary]) -> [Double] {
        course.stages.compactMap { stage in
            guard let check = stage.checkLesson else { return nil }
            return CourseGate.scoredChecks(course: course, checkLessonId: check.id, sessions: sessions)
                .filter { $0.stars >= stage.gate }
                .map(\.speed)
                .max()
        }
    }

    private static func average(_ speeds: [Double]) -> Double? {
        speeds.isEmpty ? nil : speeds.reduce(0, +) / Double(speeds.count)
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
