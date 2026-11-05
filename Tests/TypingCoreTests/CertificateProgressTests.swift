import Foundation
import Testing
@testable import TypingCore

// «Сертификат заранее» (спецификация фазы 8, §4, решение 6): сколько этапов сдано и средняя проверок до выдачи.

private func check(_ id: String, cpm: Double, accuracy: Double = 1) -> SessionSummary {
    SessionSummary(day: "2027-01-10", endedAt: .now, language: .ru, mode: .course, chars: 60, activeSeconds: 60,
                   accuracy: accuracy, completed: true, lessonId: id, exerciseKind: .check, cpm: cpm)
}

@Test func progressCountsPassedStagesAndKeepsTheAverage() throws {
    let course = try CourseFixtures.ruMini()
    // Сдан этап 1 (уроки и проверка с порогом), этап 2 — только уроки без проверки.
    let stage1 = Set(course.stages[0].lessons.map(\.id))
    let progress = Certificate.progress(course: course, passed: stage1, sessions: [check("ru2.s1.check", cpm: 98)])
    #expect(progress.stagesPassed == 1)
    #expect(progress.stagesTotal == course.stages.count)
    #expect(progress.required == Certificate.minimumAverageCpm)
    #expect(progress.required == 120)
    #expect(progress.averageCheckCpm == 98)    // средняя по уже сданным проверкам; условие получения — отдельно
    #expect(!progress.earned)
}

@Test func progressWithoutChecksHasNoAverage() throws {
    let course = try CourseFixtures.ruMini()
    let progress = Certificate.progress(course: course, passed: [], sessions: [])
    #expect(progress.stagesPassed == 0)
    #expect(progress.averageCheckCpm == nil)
    #expect(!progress.earned)
}

@Test func progressIsEarnedWhenTheCourseIsDoneAndAverageIsEnough() throws {
    let course = try CourseFixtures.ruMini()
    let all = Set(course.lessons.map(\.id))
    let fast = [check("ru2.s1.check", cpm: 100), check("ru2.s2.check", cpm: 150)]
    let done = Certificate.progress(course: course, passed: all, sessions: fast)
    #expect(done.stagesPassed == done.stagesTotal)
    #expect(done.averageCheckCpm == 125)
    #expect(done.earned)
    let slow = Certificate.progress(course: course, passed: all, sessions: [check("ru2.s1.check", cpm: 100),
                                                                            check("ru2.s2.check", cpm: 130)])
    #expect(slow.averageCheckCpm == 115)
    #expect(!slow.earned)
}
