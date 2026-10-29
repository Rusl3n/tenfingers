import Foundation
import Testing
@testable import TypingCore

/// Завершённая (или брошенная) попытка шага курса со скоростью `cpm`; `minute` — порядок по `endedAt`.
private func attempt(_ lessonId: String, _ kind: ExerciseKind = .check, cpm: Double, minute: Int = 0,
                     completed: Bool = true, mode: ExerciseMode = .course) -> SessionSummary {
    SessionSummary(day: "2026-10-25", endedAt: Date(timeIntervalSince1970: Double(minute) * 60), language: .ru,
                   mode: mode, chars: 300, activeSeconds: 60, accuracy: 0.98, completed: completed,
                   lessonId: lessonId, exerciseKind: kind, cpm: cpm)
}

@Test func speedupReferenceIsBestFinishedSpeedupCheck() throws {
    let course = try CourseFixtures.ruMini()
    let sessions = [attempt("ru2.s2.02", cpm: 150, minute: 1), attempt("ru2.s2.02", cpm: 170, minute: 2),
                    attempt("ru2.s2.02", cpm: 300, minute: 3, completed: false),
                    // Шаг не проверки урока «Ускорение» и проверки других уроков ориентиром не становятся.
                    attempt("ru2.s2.02", .words, cpm: 400, minute: 4), attempt("ru2.s1.01", cpm: 250, minute: 5)]
    #expect(SpeedupReference.reference(course: course, sessions: sessions) == 170)
}

@Test func speedupReferenceFallsBackToAverageOfLastFiveCourseChecks() throws {
    let course = try CourseFixtures.ruMini()
    // Порядок в массиве не важен: последние пять — по `endedAt` (110 … 200).
    let speeds: [(Double, Int)] = [(200, 6), (100, 1), (120, 3), (110, 2), (140, 5), (130, 4)]
    var sessions = speeds.map { attempt("ru2.s1.01", cpm: $0.0, minute: $0.1) }
    // Не проверки, брошенные и не курс — мимо; урок издания 1 считается.
    sessions.append(attempt("ru2.s1.02", .words, cpm: 900, minute: 7))
    sessions.append(attempt("ru2.s1.02", cpm: 900, minute: 8, completed: false))
    sessions.append(attempt("ru2.s1.02", cpm: 900, minute: 9, mode: .practice))
    #expect(SpeedupReference.reference(course: course, sessions: sessions) == 140)
    sessions.append(attempt("ru.1.1", cpm: 260, minute: 10))
    #expect(SpeedupReference.reference(course: course, sessions: sessions) == 170) // 120 … 260
}

@Test func speedupWordsStepIsNotAReference() throws {
    let course = try CourseFixtures.ruMini()
    let sessions = [attempt("ru2.s2.02", .words, cpm: 150), attempt("ru2.s1.01", cpm: 90, minute: 1)]
    #expect(SpeedupReference.reference(course: course, sessions: sessions) == 90)
}

@Test func noChecksMeansNoReference() throws {
    let course = try CourseFixtures.ruMini()
    #expect(SpeedupReference.reference(course: course, sessions: []) == nil)
    #expect(SpeedupReference.reference(course: course,
                                       sessions: [attempt("ru2.s2.02", .sprint, cpm: 150)]) == nil)
}

@Test func speedupGoalAndOutcome() {
    #expect(SpeedupReference.goal(reference: 142) == 149)
    #expect(SpeedupReference.outcome(cpm: 150.2, reference: 142) == .beaten(percent: 6))
    #expect(SpeedupReference.outcome(cpm: 142.1, reference: 142) == .beaten(percent: 1))
    #expect(SpeedupReference.outcome(cpm: 138, reference: 142) == .short(cpm: 4))
    #expect(SpeedupReference.outcome(cpm: 142, reference: 142) == .short(cpm: 1))
    // Ровно +5% не превращается в +6% из-за двоичной арифметики.
    #expect(SpeedupReference.outcome(cpm: 149.1, reference: 142) == .beaten(percent: 5))
}
