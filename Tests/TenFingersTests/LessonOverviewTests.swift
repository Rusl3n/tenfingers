import Foundation
import SwiftData
import Testing
import TypingCore
@testable import TenFingers

private func check(_ lessonId: String, accuracy: Double, cpm: Double, kind: String = "check",
                   completed: Bool = true) -> SessionRecord {
    let end = Date(timeIntervalSince1970: 1_773_144_000)
    return SessionRecord(mode: "course", language: "ru", lessonId: lessonId, startedAt: end.addingTimeInterval(-60),
                         endedAt: end, logicalDay: "2026-03-10", activeSeconds: 60, chars: Int(cpm), errorCount: 1,
                         cpm: cpm, accuracy: accuracy, completed: completed, hintLevel: "full", maxErrorStreak: 0,
                         wrongKeystrokes: 0, exerciseKind: kind)
}

@MainActor @Test func starsAreRecomputedFromHistoryNotStoredBest() throws {
    let container = try ModelStore.makeContainer(inMemory: true)
    defer { withExtendedLifetime(container) {} }
    let context = container.mainContext
    // Старая база: по прежнему правилу записано ★★★, а по истории с учётом точности — ★★.
    let progress = LessonProgress(lessonId: "ru.1.1", language: "ru")
    progress.bestStars = 3
    progress.passedAt = .now
    context.insert(progress)
    context.insert(check("ru.1.1", accuracy: 0.99, cpm: 120))
    context.insert(check("ru.1.1", accuracy: 0.97, cpm: 200))
    try context.save()

    let sessions = try ProgressSnapshot(context: context).lessonSessions(lessonId: "ru.1.1")
    let overview = LessonOverview.make(lessonId: "ru.1.1", targetCpm: 60, sessions: sessions, storedStars: progress.bestStars)
    #expect(overview.stars == 2)
    #expect(progress.bestStars == 3) // данные пользователя не меняются
}

@Test func historyWithPerfectCheckGivesThreeStars() {
    let sessions = [
        SessionSummary(day: "d", endedAt: .now, language: .ru, mode: .course, chars: 90, activeSeconds: 60,
                       accuracy: 1.0, completed: true, lessonId: "ru.1.1", exerciseKind: .check, cpm: 90),
        SessionSummary(day: "d", endedAt: .now, language: .ru, mode: .course, chars: 120, activeSeconds: 60,
                       accuracy: 0.97, completed: true, lessonId: "ru.1.1", exerciseKind: .check, cpm: 120),
    ]
    #expect(LessonOverview.make(lessonId: "ru.1.1", targetCpm: 60, sessions: sessions, storedStars: 0).stars == 3)
}

@Test func withoutCheckHistoryStoredStarsAreKept() {
    // Проверок в истории нет (например, записи старых версий без шага): звёзды из базы не теряются.
    let overview = LessonOverview.make(lessonId: "ru.1.1", targetCpm: 60, sessions: [], storedStars: 2)
    #expect(overview.stars == 2)
    #expect(overview.steps.isEmpty && overview.averageAccuracy == nil)
}

@Test func overviewHasStepsAndAverage() {
    let sessions = [
        SessionSummary(day: "d", endedAt: .now, language: .ru, mode: .course, chars: 80, activeSeconds: 60,
                       accuracy: 1.0, completed: true, lessonId: "ru.1.1", exerciseKind: .drill, cpm: 80),
        SessionSummary(day: "d", endedAt: .now, language: .ru, mode: .course, chars: 80, activeSeconds: 60,
                       accuracy: 0.946, completed: true, lessonId: "ru.1.1", exerciseKind: .words, cpm: 80,
                       errorCount: 5),
    ]
    let overview = LessonOverview.make(lessonId: "ru.1.1", targetCpm: 60, sessions: sessions, storedStars: 0)
    #expect(overview.steps.map(\.kind) == [.drill, .words])
    #expect(abs((overview.averageAccuracy ?? 0) - 0.973) < 1e-9)
    #expect(overview.stars == 0)
}

/// Урок пройден до появления шагов в истории (или проверки после — неудачные): не меньше одной звезды.
@Test func passedLessonShowsAtLeastOneStar() {
    #expect(LessonOverview.make(lessonId: "ru.1.1", targetCpm: 60, sessions: [], storedStars: 0, isPassed: true).stars == 1)
    let failedCheck = SessionSummary(day: "d", endedAt: .now, language: .ru, mode: .course, chars: 60, activeSeconds: 60,
                                     accuracy: 0.9, completed: true, lessonId: "ru.1.1", exerciseKind: .check, cpm: 60)
    #expect(LessonOverview.make(lessonId: "ru.1.1", targetCpm: 60, sessions: [failedCheck], storedStars: 2,
                                isPassed: true).stars == 1)
    #expect(LessonOverview.make(lessonId: "ru.1.1", targetCpm: 60, sessions: [failedCheck], storedStars: 2,
                                isPassed: false).stars == 0)
    #expect(LessonOverview.make(lessonId: "ru.1.1", targetCpm: 60, sessions: [], storedStars: 3, isPassed: true).stars == 3)
}

/// Половина пробела для подсказки — только когда ожидается пробел.
@MainActor @Test func spaceHalfOnlyForSpaceKey() {
    #expect(KeyboardView.spaceHalf(for: nil) == nil)
    #expect(KeyboardView.spaceHalf(for: KeyHighlight(keyCode: KeyboardGeometry.space, shiftKeyCode: nil, isError: false,
                                                      spaceThumb: .left)) == .left)
    #expect(KeyboardView.spaceHalf(for: KeyHighlight(keyCode: KeyboardGeometry.space, shiftKeyCode: nil, isError: true,
                                                      spaceThumb: .right)) == .right)
    #expect(KeyboardView.spaceHalf(for: KeyHighlight(keyCode: KeyboardGeometry.space, shiftKeyCode: nil,
                                                      isError: false)) == nil)
    // Другая клавиша: даже с рукой пробел не подсвечивается половиной.
    #expect(KeyboardView.spaceHalf(for: KeyHighlight(keyCode: 3, shiftKeyCode: nil, isError: false,
                                                      spaceThumb: .left)) == nil)
}

@Test func lessonRunKeepsOptionalSingleStep() {
    #expect(LessonRun(language: .ru, lessonId: "ru.1.1").onlyStep == nil)
    #expect(LessonRun(language: .ru, lessonId: "ru.1.1", onlyStep: .combos).onlyStep == .combos)
}
