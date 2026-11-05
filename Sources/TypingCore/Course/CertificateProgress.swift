import Foundation

/// Где курс на пути к «Сертификату» (спецификация фазы 8, §4): сколько этапов сдано, средняя скорость проверок этапов и
/// выдан ли он уже. Условие то же, что у `Certificate.eligibleAverage`.
public struct CertificateProgress: Equatable, Sendable {
    public let stagesPassed: Int
    public let stagesTotal: Int
    /// Средняя по уже сданным проверкам этапов (для показа); `nil` — ни одной. Условие получения — `earned`.
    public let averageCheckCpm: Double?
    /// Нужная средняя (`Certificate.minimumAverageCpm`).
    public let required: Double
    /// Курс пройден и средняя не ниже нужной.
    public let earned: Bool

    public init(stagesPassed: Int, stagesTotal: Int, averageCheckCpm: Double?, required: Double, earned: Bool) {
        self.stagesPassed = stagesPassed
        self.stagesTotal = stagesTotal
        self.averageCheckCpm = averageCheckCpm
        self.required = required
        self.earned = earned
    }
}

extension Certificate {
    /// Этап сдан: все его уроки засчитаны и проверка этапа (если есть) взяла порог.
    /// `checkStars` берутся из `sessions` — как в `eligibleAverage`, чтобы условие не расходилось.
    public static func progress(course: Course, passed: Set<String>, sessions: [SessionSummary]) -> CertificateProgress {
        let stars = CourseGate.checkStars(course: course, sessions: sessions)
        let done = course.stages.filter { stage in
            stage.lessons.allSatisfy { passed.contains($0.id) }
                && (stage.checkLesson.map { (stars[$0.id] ?? 0) >= stage.gate } ?? true)
        }.count
        return CertificateProgress(
            stagesPassed: done, stagesTotal: course.stages.count,
            averageCheckCpm: passedChecksAverageCpm(course: course, sessions: sessions), required: minimumAverageCpm,
            earned: eligibleAverage(course: course, passed: passed, sessions: sessions) != nil)
    }
}
