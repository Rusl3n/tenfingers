import Foundation
import Testing
@testable import TypingCore

// Статистика урока с прогрессией (фаза 8a, задача 6b): проходы-проверки и рост скорости по шагам.

private func session(_ day: Int, lesson: String? = "L1", kind: ExerciseKind? = .check, cpm: Double = 150,
                     errors: Int = 0, accuracy: Double = 1, completed: Bool = true, mode: ExerciseMode = .course,
                     step: Int? = nil) -> SessionSummary {
    SessionSummary(day: "2026-10-\(day)", endedAt: Date(timeIntervalSince1970: Double(day) * 86_400), language: .ru,
                   mode: mode, chars: 100, activeSeconds: 40, accuracy: accuracy, completed: completed,
                   lessonId: lesson, exerciseKind: kind, cpm: cpm, errorCount: errors, stepIndex: step)
}

@Test func lessonHistoryEmpty() {
    let stats = LessonHistory.make(lessonId: "L1", sessions: [], targetCpm: 160)
    #expect(stats.passes.isEmpty && stats.steps.isEmpty && stats.firstDate == nil && stats.lastDate == nil)
}

@Test func lessonHistoryPassesOnlyCompletedChecksOfThisLesson() {
    let sessions = [
        session(5, cpm: 171), session(2, cpm: 142, errors: 6, accuracy: 0.94), session(9, cpm: 196),
        session(3, lesson: "L2"),                              // чужой урок
        session(4, completed: false),                          // незавершённая
        session(6, mode: .practice),                           // не курс
        session(7, kind: .words, step: 2),                     // шаг, не проверка
        session(8, kind: .refresh, cpm: 160),                  // «Освежить» — проход
    ]
    let stats = LessonHistory.make(lessonId: "L1", sessions: sessions, targetCpm: 160)
    #expect(stats.passes.map(\.cpm) == [142, 171, 160, 196])   // по времени
    #expect(stats.passes[0].errors == 6)
    #expect(stats.firstDate == sessions[1].endedAt && stats.lastDate == sessions[2].endedAt)
}

@Test func lessonHistoryStarsMatchCheckScoring() throws {
    let course = try CourseFixtures.ruMini()
    let check = try #require(course.stages[0].checkLesson).id
    let target = try #require(course.targetCpm(for: check))
    let sessions = [session(1, lesson: check, cpm: Double(target) * 1.4, accuracy: 0.999),
                    session(2, lesson: check, cpm: Double(target) * 0.5, accuracy: 0.97),
                    session(3, lesson: check, kind: .refresh, cpm: Double(target), accuracy: 0.98)]
    let stats = LessonHistory.make(lessonId: check, sessions: sessions, targetCpm: target)
    let scored = CourseGate.scoredChecks(course: course, checkLessonId: check, sessions: sessions)
    #expect(stats.passes.map(\.stars) == scored.map(\.stars))
    #expect(stats.passes.map(\.cpm) == scored.map(\.speed))
}

@Test func lessonHistoryStepProgress() {
    let sessions = [
        session(1, kind: .drill, cpm: 120, step: 0), session(9, kind: .drill, cpm: 188, step: 0),
        session(3, kind: .words, cpm: 131, step: 1), session(5, kind: .words, cpm: 150, step: 1),
        session(7, kind: .words, cpm: 176, step: 1),
        session(2, kind: .phrases, cpm: 90, step: 2),                      // одна запись — без роста
        session(4, kind: .drill, cpm: 10, completed: false, step: 0),      // незавершённая не в счёт
        session(6, kind: .check, cpm: 300),                                // проверка — не шаг
    ]
    let steps = LessonHistory.make(lessonId: "L1", sessions: sessions, targetCpm: 160).steps
    #expect(steps.map(\.stepIndex) == [0, 1, 2])
    #expect(steps[0].first == 120 && steps[0].last == 188 && steps[0].changePercent == 57)
    #expect(steps[1].first == 131 && steps[1].last == 176 && steps[1].changePercent == 34)
    #expect(steps[2].changePercent == nil && steps[2].runs == 1)
}

@Test func lessonHistoryArchivedStepsGroupByKind() {
    let sessions = [session(1, kind: .words, cpm: 100), session(3, kind: .drill, cpm: 80),
                    session(2, kind: .words, cpm: 120), session(4, kind: .words, cpm: 90)]
    let steps = LessonHistory.make(lessonId: "L1", sessions: sessions, targetCpm: 160).steps
    #expect(steps.map(\.kind) == [.words, .drill] && steps.allSatisfy { $0.stepIndex == nil })
    #expect(steps[0].first == 100 && steps[0].last == 90 && steps[0].changePercent == -10 && steps[0].runs == 3)
    #expect(steps[1].changePercent == nil)
}
