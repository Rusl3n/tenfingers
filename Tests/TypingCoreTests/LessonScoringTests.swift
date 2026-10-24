import Testing
@testable import TypingCore

// «Действующая» оценка урока: единственное место, где складываются история проверок, зачёт и сохранённые звёзды.

@Test func effectiveStarsRecomputesFromHistoryByCurrentRule() {
    // 60 зн/мин — цель; 80 при 99,6% — три звезды (60 × 1,3 = 78)
    let history = [(cpm: 50.0, accuracy: 0.97), (cpm: 80.0, accuracy: 0.996)]
    #expect(LessonScoring.effectiveStars(history: history, targetCpm: 60, passed: true, storedStars: 1) == 3)
    // история важнее базы: в базе 3, а по правилу лучшая проверка даёт 1
    #expect(LessonScoring.effectiveStars(history: [(cpm: 10, accuracy: 0.97)], targetCpm: 60, passed: true,
                                         storedStars: 3) == 1)
}

@Test func effectiveStarsFallsBackToStoredWhenNoHistory() {
    #expect(LessonScoring.effectiveStars(history: [], targetCpm: 60, passed: true, storedStars: 2) == 2)
    #expect(LessonScoring.effectiveStars(history: [], targetCpm: 60, passed: false, storedStars: 2) == 2)
    #expect(LessonScoring.effectiveStars(history: [], targetCpm: 60, passed: false, storedStars: 0) == 0)
}

@Test func effectiveStarsOfPassedLessonIsAtLeastOne() {
    #expect(LessonScoring.effectiveStars(history: [], targetCpm: 60, passed: true, storedStars: 0) == 1)
    // неудачная проверка после прохождения не отменяет зачёта
    #expect(LessonScoring.effectiveStars(history: [(cpm: 500, accuracy: 0.5)], targetCpm: 60, passed: true,
                                         storedStars: 2) == 1)
    // не засчитан — нулевая оценка остаётся нулевой
    #expect(LessonScoring.effectiveStars(history: [(cpm: 500, accuracy: 0.5)], targetCpm: 60, passed: false,
                                         storedStars: 2) == 0)
}

@Test func effectiveStarsFromSessionsUsesOnlyCompletedChecksOfTheLesson() {
    func session(_ id: String, _ kind: ExerciseKind, cpm: Double, accuracy: Double, completed: Bool = true) -> SessionSummary {
        SessionSummary(day: "2026-09-21", endedAt: .distantPast, language: .ru, mode: .course, chars: 100,
                       activeSeconds: 60, accuracy: accuracy, completed: completed, lessonId: id,
                       exerciseKind: kind, cpm: cpm)
    }
    let sessions = [
        session("ru.1.1", .check, cpm: 80, accuracy: 0.996),                    // три звезды
        session("ru.1.2", .check, cpm: 80, accuracy: 0.996),                    // другой урок
        session("ru.1.1", .drill, cpm: 500, accuracy: 1),                       // не проверка
        session("ru.1.1", .check, cpm: 500, accuracy: 1, completed: false),     // не завершена
    ]
    #expect(LessonScoring.effectiveStars(sessions: sessions, lessonId: "ru.1.1", targetCpm: 60, passed: true,
                                         storedStars: 0) == 3)
    #expect(LessonScoring.effectiveStars(sessions: sessions, lessonId: "ru.1.3", targetCpm: 60, passed: true,
                                         storedStars: 2) == 2)
}
