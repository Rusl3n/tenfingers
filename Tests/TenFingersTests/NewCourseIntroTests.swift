import Foundation
import SwiftData
import Testing
import TypingCore
@testable import TenFingers

@Test func introShowsOnlyWithEditionOneProgressAndNoFlag() {
    let (defaults, name) = makeTestDefaults("TenFingersTests.NewCourseIntro.")
    defer { removeTestDefaults(name) }
    #expect(NewCourseIntro.shouldShow(lessonIds: ["ru.1.1"], defaults: defaults))
    #expect(NewCourseIntro.shouldShow(lessonIds: ["ru2.s1.01", "en.2.3"], defaults: defaults))
    #expect(!NewCourseIntro.shouldShow(lessonIds: ["ru2.s1.01"], defaults: defaults))
    #expect(!NewCourseIntro.shouldShow(lessonIds: [], defaults: defaults))
}

@Test func introIsNotShownAgainAfterMarkShown() {
    let (defaults, name) = makeTestDefaults("TenFingersTests.NewCourseIntro.")
    defer { removeTestDefaults(name) }
    NewCourseIntro.markShown(defaults)
    #expect(defaults.bool(forKey: SettingsKey.newCourseIntroShown))
    #expect(!NewCourseIntro.shouldShow(lessonIds: ["ru.1.1"], defaults: defaults))
}

@Test func purgeRemovesResumeOfLessonsOutsideCurrentCourses() {
    let (defaults, name) = makeTestDefaults("TenFingersTests.NewCourseIntro.")
    defer { removeTestDefaults(name) }
    let state = LessonResumeState(completedSteps: 2, totalSteps: 4, updatedAt: Date(timeIntervalSince1970: 1_800_000_000))
    let resume = LessonResume(defaults: defaults)
    for id in ["ru.1.1", "en.2.3", "ru2.s1.01"] { resume.stepFinished(lessonId: id, index: 1, totalSteps: 4, now: state.updatedAt) }
    defaults.set("always", forKey: SettingsKey.hintMode)

    resume.purge(keeping: ["ru2.s1.01"])
    #expect(defaults.object(forKey: "lessonResume.ru.1.1") == nil)
    #expect(defaults.object(forKey: "lessonResume.en.2.3") == nil)
    #expect(resume.load(lessonId: "ru2.s1.01") == state)
    #expect(defaults.string(forKey: SettingsKey.hintMode) == "always")

    resume.purge(keeping: ["ru2.s1.01"])
    #expect(resume.load(lessonId: "ru2.s1.01") == state)
    #expect(defaults.string(forKey: SettingsKey.hintMode) == "always")
}

/// Сессии прежнего курса в истории сохраняют названия уроков: поиск в `legacyCourses`, когда в текущем курсе нет.
@Test func historyTitleFallsBackToEditionOneCourse() throws {
    let current = try CourseCatalog.load(.ru)
    let legacy = try #require(try CourseCatalog.legacy(.ru))
    let old = legacy.lessons[0]
    #expect(SessionHistory.lessonTitle(lessonId: old.id, kind: nil, course: current) == nil)
    #expect(SessionHistory.lessonTitle(lessonId: old.id, kind: nil, course: current, legacy: legacy) == "\(old.localizedTitle) (курс 1.x)")
    let new = current.lessons[0]
    #expect(SessionHistory.lessonTitle(lessonId: new.id, kind: nil, course: current, legacy: legacy) == new.localizedTitle)
}
