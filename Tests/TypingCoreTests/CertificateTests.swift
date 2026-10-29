import Foundation
import Testing
@testable import TypingCore

// «Сертификат»: курс издания 2 пройден и средняя скорость лучших проверок этапов, взявших порог, не ниже 120
// (спецификация фазы 6, §16, решение 18). Цель проверки этапа 1 — 80 (порог ★★), этапа 2 — 110 (порог ★★★).

private func check(_ id: String, cpm: Double, accuracy: Double = 1, kind: ExerciseKind = .check,
                   completed: Bool = true) -> SessionSummary {
    SessionSummary(day: "2027-01-10", endedAt: .now, language: .ru, mode: .course, chars: 60, activeSeconds: 60,
                   accuracy: accuracy, completed: completed, lessonId: id, exerciseKind: kind, cpm: cpm)
}

@Test func averageTakesTheBestCheckOfEveryStageThatReachedTheGate() throws {
    let course = try CourseFixtures.ruMini()
    let sessions = [
        check("ru2.s1.check", cpm: 90),
        check("ru2.s1.check", cpm: 100),
        check("ru2.s1.check", cpm: 300, accuracy: 0.9),      // не засчитана: порога нет
        check("ru2.s1.check", cpm: 300, completed: false),
        check("ru2.s1.check", cpm: 300, kind: .words),
        check("ru2.s2.check", cpm: 150),
        check("ru2.s1.01", cpm: 300),                        // не проверка этапа
    ]
    #expect(Certificate.averageCheckCpm(course: course, sessions: sessions) == 125)
}

@Test func averageIsNilWhenAStageBestCheckMissedTheGate() throws {
    let course = try CourseFixtures.ruMini()
    // Этап 2: лучшая проверка 95 зн/мин — ★★ при пороге ★★★.
    let sessions = [check("ru2.s1.check", cpm: 100), check("ru2.s2.check", cpm: 95)]
    #expect(Certificate.averageCheckCpm(course: course, sessions: sessions) == nil)
    #expect(Certificate.averageCheckCpm(course: course, sessions: [check("ru2.s1.check", cpm: 100)]) == nil)
    #expect(Certificate.averageCheckCpm(course: course, sessions: []) == nil)
}

@Test func eligibleAverageNeedsACompletedCourseAndAtLeast120() throws {
    let course = try CourseFixtures.ruMini()
    let all = Set(course.lessons.map(\.id))
    let fast = [check("ru2.s1.check", cpm: 100), check("ru2.s2.check", cpm: 150)]
    let slow = [check("ru2.s1.check", cpm: 100), check("ru2.s2.check", cpm: 130)]    // (100 + 130) / 2 = 115
    #expect(Certificate.minimumAverageCpm == 120)
    #expect(Certificate.eligibleAverage(course: course, passed: all, sessions: fast) == 125)
    #expect(Certificate.eligibleAverage(course: course, passed: all, sessions: slow) == nil)
    // Курс не пройден: не засчитан один урок.
    #expect(Certificate.eligibleAverage(course: course, passed: all.subtracting(["ru2.s1.03"]), sessions: fast) == nil)
    // Ровно 120 — достаточно.
    let edge = [check("ru2.s1.check", cpm: 90), check("ru2.s2.check", cpm: 150)]
    #expect(Certificate.eligibleAverage(course: course, passed: all, sessions: edge) == 120)
}

@Test func editionOneHasNoCertificate() throws {
    let course = try #require(try CourseCatalog.legacy(.ru))
    let all = Set(course.lessons.map(\.id))
    #expect(Certificate.eligibleAverage(course: course, passed: all, sessions: []) == nil)
}
