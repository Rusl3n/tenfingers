import Foundation
import Testing
@testable import TypingCore

/// Завершённая (или брошенная) попытка шага курса со скоростью `cpm`; `minute` — порядок по `endedAt`.
private func attempt(_ lessonId: String, _ kind: ExerciseKind = .words, cpm: Double, minute: Int = 0,
                     completed: Bool = true, mode: ExerciseMode = .course, accuracy: Double = 0.98) -> SessionSummary {
    SessionSummary(day: "2026-10-25", endedAt: Date(timeIntervalSince1970: Double(minute) * 60), language: .ru,
                   mode: mode, chars: 300, activeSeconds: 60, accuracy: accuracy, completed: completed,
                   lessonId: lessonId, exerciseKind: kind, cpm: cpm)
}

/// `count` завершённых шагов обычного урока подряд со скоростью `cpm`, начиная с минуты `from`.
private func steps(_ count: Int, cpm: Double, from: Int = 0, lessonId: String = "ru2.s1.01") -> [SessionSummary] {
    (0..<count).map { attempt(lessonId, cpm: cpm, minute: from + $0) }
}

@Test func referenceIsAverageOfLastThirtyCourseSteps() throws {
    let course = try CourseFixtures.ruMini()
    // 10 старых шагов по 300 выпадают из окна: считаются последние 30 по `endedAt` (порядок в массиве не важен).
    let sessions = (steps(20, cpm: 200, from: 20) + steps(10, cpm: 300) + steps(10, cpm: 170, from: 40)).shuffled()
    #expect(SpeedupReference.reference(course: course, sessions: sessions) == 190) // (20·200 + 10·170) / 30
}

@Test func referenceCountsAnyStepKindOfRegularLessons() throws {
    let course = try CourseFixtures.ruMini()
    var sessions = steps(8, cpm: 100)
    sessions.append(attempt("ru2.s1.check", .check, cpm: 160, minute: 20))
    sessions.append(attempt("ru2.s1.01", .refresh, cpm: 160, minute: 21))
    #expect(SpeedupReference.reference(course: course, sessions: sessions) == 112) // (8·100 + 2·160) / 10
}

@Test func speedupLessonStepsAreNotPartOfTheReference() throws {
    let course = try CourseFixtures.ruMini()
    // Шаги самого «Ускорения» (сильные буквы, спринты) быстрее обычных и цель за собой не тянут.
    let sessions = steps(10, cpm: 150) + [attempt("ru2.s2.02", .sprint, cpm: 400, minute: 50),
                                          attempt("ru2.s2.02", .check, cpm: 300, minute: 51)]
    #expect(SpeedupReference.reference(course: course, sessions: sessions) == 150)
}

@Test func unfinishedAndNonCourseSessionsAreNotPartOfTheReference() throws {
    let course = try CourseFixtures.ruMini()
    var sessions = steps(10, cpm: 150)
    sessions.append(attempt("ru2.s1.01", cpm: 900, minute: 30, completed: false))
    sessions.append(attempt("ru2.s1.01", cpm: 900, minute: 31, mode: .practice))
    #expect(SpeedupReference.reference(course: course, sessions: sessions) == 150)
}

@Test func fewerThanTenStepsMeansNoReference() throws {
    let course = try CourseFixtures.ruMini()
    #expect(SpeedupReference.reference(course: course, sessions: []) == nil)
    #expect(SpeedupReference.reference(course: course, sessions: steps(9, cpm: 150)) == nil)
    #expect(SpeedupReference.reference(course: course, sessions: steps(10, cpm: 150)) == 150)
}

@Test func speedupGoalIsTenPercentAboveTheAverage() {
    #expect(SpeedupReference.goal(reference: 196) == 216) // 215,6
    #expect(SpeedupReference.goal(reference: 150) == 165)
    #expect(SpeedupReference.goal(reference: 142) == 156) // 156,2
}

@Test func speedupOutcomeIsAgainstTheGoal() {
    #expect(SpeedupReference.outcome(cpm: 216, goal: 216) == .reached)
    #expect(SpeedupReference.outcome(cpm: 230.4, goal: 216) == .reached)
    #expect(SpeedupReference.outcome(cpm: 209, goal: 216) == .short(cpm: 7))
    // Нехватка округляется вверх и не бывает нулём.
    #expect(SpeedupReference.outcome(cpm: 215.9, goal: 216) == .short(cpm: 1))
    #expect(SpeedupReference.outcome(cpm: 208.5, goal: 216) == .short(cpm: 8))
}
