import Foundation
import Testing
@testable import TenFingers

/// Изолированное хранилище на тест: стандартные настройки пользователя не трогаем; удаляется в `defer`.
private func isolatedDefaults() -> (UserDefaults, String) {
    makeTestDefaults("TenFingersTests.LessonResume.")
}

private let now = Date(timeIntervalSince1970: 1_800_000_000)

@Test func nextStartIsFirstUnfinishedStep() {
    let saved = LessonResumeState(completedSteps: 2, totalSteps: 4, updatedAt: now)
    #expect(LessonResume.nextStart(saved: saved, totalSteps: 4) == 2)
}

@Test func nextStartIgnoresMissingFinishedOrMismatchedState() {
    #expect(LessonResume.nextStart(saved: nil, totalSteps: 4) == 0)
    #expect(LessonResume.nextStart(saved: LessonResumeState(completedSteps: 0, totalSteps: 4, updatedAt: now), totalSteps: 4) == 0)
    #expect(LessonResume.nextStart(saved: LessonResumeState(completedSteps: 4, totalSteps: 4, updatedAt: now), totalSteps: 4) == 0)
    // План урока изменился: число шагов другое.
    #expect(LessonResume.nextStart(saved: LessonResumeState(completedSteps: 2, totalSteps: 4, updatedAt: now), totalSteps: 3) == 0)
}

@Test func stateAfterStepCountsCompletedStepsAndClearsAfterLast() {
    #expect(LessonResume.state(afterStep: 0, totalSteps: 4, now: now)
            == LessonResumeState(completedSteps: 1, totalSteps: 4, updatedAt: now))
    #expect(LessonResume.state(afterStep: 2, totalSteps: 4, now: now)?.completedSteps == 3)
    #expect(LessonResume.state(afterStep: 3, totalSteps: 4, now: now) == nil)
}

@Test func resumeIsStoredPerLessonAndCleared() {
    let (defaults, name) = isolatedDefaults()
    defer { removeTestDefaults(name) }
    let resume = LessonResume(defaults: defaults)
    resume.stepFinished(lessonId: "ru.1.1", index: 0, totalSteps: 4, now: now)
    resume.stepFinished(lessonId: "ru.1.1", index: 1, totalSteps: 4, now: now)
    #expect(resume.load(lessonId: "ru.1.1") == LessonResumeState(completedSteps: 2, totalSteps: 4, updatedAt: now))
    #expect(resume.load(lessonId: "ru.1.2") == nil)
    #expect(resume.start(lessonId: "ru.1.1", totalSteps: 4) == 2)
    resume.stepFinished(lessonId: "ru.1.1", index: 3, totalSteps: 4, now: now) // последний шаг
    #expect(resume.load(lessonId: "ru.1.1") == nil)
    #expect(resume.start(lessonId: "ru.1.1", totalSteps: 4) == 0)
}

@Test func mismatchedResumeIsDroppedOnStart() {
    let (defaults, name) = isolatedDefaults()
    defer { removeTestDefaults(name) }
    let resume = LessonResume(defaults: defaults)
    resume.stepFinished(lessonId: "ru.1.1", index: 1, totalSteps: 4, now: now)
    #expect(resume.start(lessonId: "ru.1.1", totalSteps: 3) == 0)
    #expect(resume.load(lessonId: "ru.1.1") == nil)
    #expect(defaults.object(forKey: "lessonResume.ru.1.1") == nil)
}

@Test func clearRemovesResume() {
    let (defaults, name) = isolatedDefaults()
    defer { removeTestDefaults(name) }
    let resume = LessonResume(defaults: defaults)
    resume.stepFinished(lessonId: "en.1.1", index: 0, totalSteps: 4, now: now)
    resume.clear(lessonId: "en.1.1")
    #expect(resume.load(lessonId: "en.1.1") == nil)
}

@Test func unreadableResumeIsIgnored() {
    let (defaults, name) = isolatedDefaults()
    defer { removeTestDefaults(name) }
    defaults.set(Data("мусор".utf8), forKey: "lessonResume.ru.1.1")
    #expect(LessonResume(defaults: defaults).start(lessonId: "ru.1.1", totalSteps: 4) == 0)
}

@Test func overLimitStepDoesNotMoveResume() {
    let (defaults, name) = isolatedDefaults()
    defer { removeTestDefaults(name) }
    let resume = LessonResume(defaults: defaults)
    resume.stepFinished(lessonId: "ru.1.1", index: 0, totalSteps: 4, now: now)
    // Шаг 2 (индекс 1) с перебором: продолжение остаётся с шага 2.
    resume.stepFinished(lessonId: "ru.1.1", index: 1, totalSteps: 4, passed: false, now: now)
    #expect(resume.start(lessonId: "ru.1.1", totalSteps: 4) == 1)
    // В допуске: с шага 3.
    resume.stepFinished(lessonId: "ru.1.1", index: 1, totalSteps: 4, passed: true, now: now)
    #expect(resume.start(lessonId: "ru.1.1", totalSteps: 4) == 2)
}

@Test func overLimitFirstStepLeavesNoResume() {
    let (defaults, name) = isolatedDefaults()
    defer { removeTestDefaults(name) }
    let resume = LessonResume(defaults: defaults)
    resume.stepFinished(lessonId: "ru.1.1", index: 0, totalSteps: 4, passed: false, now: now)
    #expect(resume.load(lessonId: "ru.1.1") == nil)
}

@Test func overLimitStepRefreshesResumeTimestamp() {
    let (defaults, name) = isolatedDefaults()
    defer { removeTestDefaults(name) }
    let resume = LessonResume(defaults: defaults)
    resume.stepFinished(lessonId: "ru.1.1", index: 0, totalSteps: 4, now: now)
    let later = now.addingTimeInterval(86_400)
    resume.stepFinished(lessonId: "ru.1.1", index: 1, totalSteps: 4, passed: false, now: later)
    #expect(resume.load(lessonId: "ru.1.1") == LessonResumeState(completedSteps: 1, totalSteps: 4, updatedAt: later))
}
