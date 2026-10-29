import Foundation
import SwiftData
import Testing
import TypingCore
@testable import TenFingers

private func utc() -> Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    return calendar
}

/// 2026-03-10 12:00 UTC: логический день «2026-03-10» при начале дня в 4 часа.
private let noon = Date(timeIntervalSince1970: 1_773_144_000)

/// Контейнер должен жить, пока используется контекст: иначе контекст указывает на освобождённое хранилище.
@MainActor
private func makeContainer() throws -> ModelContainer {
    try ModelStore.makeContainer(inMemory: true)
}

private func day(_ key: String, seconds: Double, completed: Int, abandoned: Int = 0) -> DayRecord {
    let record = DayRecord(logicalDay: key)
    record.activeSeconds = seconds
    record.completedExercises = completed
    record.abandonedExercises = abandoned
    return record
}

private func session(day: String, language: Language = .ru, mode: ExerciseMode = .course, chars: Int = 100,
                     seconds: Double = 60, accuracy: Double = 0.95, completed: Bool = true,
                     endedAt: Date = noon) -> SessionRecord {
    SessionRecord(mode: mode.rawValue, language: language.rawValue, lessonId: nil, startedAt: endedAt.addingTimeInterval(-seconds),
                  endedAt: endedAt, logicalDay: day, activeSeconds: seconds, chars: chars, errorCount: 0,
                  cpm: Double(chars) / seconds * 60, accuracy: accuracy, completed: completed,
                  hintLevel: "full", maxErrorStreak: 0, wrongKeystrokes: 0)
}

@MainActor @Test func dayActivitiesMapsDayRecords() throws {
    let container = try makeContainer()
    defer { withExtendedLifetime(container) {} }
    let context = container.mainContext
    context.insert(day("2026-03-09", seconds: 700, completed: 3))
    context.insert(day("2026-03-10", seconds: 90, completed: 0, abandoned: 1))
    let days = try ProgressSnapshot(context: context).dayActivities()
    #expect(days == [
        "2026-03-09": DayActivity(activeSeconds: 700, completedExercises: 3),
        "2026-03-10": DayActivity(activeSeconds: 90, completedExercises: 0),
    ])
}

@MainActor @Test func sessionSummariesMapAndSkipUnknownValues() throws {
    let container = try makeContainer()
    defer { withExtendedLifetime(container) {} }
    let context = container.mainContext
    context.insert(session(day: "2026-03-10", language: .en, mode: .adaptive, chars: 200, seconds: 80, accuracy: 0.9, completed: false))
    let broken = session(day: "2026-03-10")
    broken.mode = "из будущего"
    context.insert(broken)
    let list = try ProgressSnapshot(context: context).sessionSummaries()
    #expect(list.count == 1)
    #expect(list[0] == SessionSummary(day: "2026-03-10", endedAt: noon, language: .en, mode: .adaptive, chars: 200,
                                      activeSeconds: 80, accuracy: 0.9, completed: false, cpm: 150))
}

@MainActor @Test func sessionSummariesCarryLessonStepAndErrors() throws {
    let container = try makeContainer()
    defer { withExtendedLifetime(container) {} }
    let context = container.mainContext
    let record = session(day: "2026-03-10", accuracy: 0.97)
    record.lessonId = "ru.1.1"
    record.exerciseKind = "combos"
    record.errorCount = 3
    context.insert(record)
    let unknownKind = session(day: "2026-03-10")
    unknownKind.lessonId = "ru.1.1"
    unknownKind.exerciseKind = "из будущего"
    context.insert(unknownKind)
    let list = try ProgressSnapshot(context: context).lessonSessions(lessonId: "ru.1.1")
    #expect(list.count == 2)
    let combos = try #require(list.first { $0.exerciseKind == .combos })
    #expect(combos.lessonId == "ru.1.1" && combos.errorCount == 3 && combos.cpm == 100)
    #expect(list.contains { $0.exerciseKind == nil })
    #expect(try ProgressSnapshot(context: context).lessonSessions(lessonId: "ru.1.2").isEmpty)
}

/// Запись шага курса для проверок гейта и ориентира «Ускорения».
private func courseStep(_ lessonId: String, kind: ExerciseKind, language: Language = .ru, cpm: Double,
                        accuracy: Double = 0.99, completed: Bool = true, endedAt: Date = noon) -> SessionRecord {
    let record = session(day: "2026-03-10", language: language, chars: 100, seconds: 60, accuracy: accuracy,
                         completed: completed, endedAt: endedAt)
    record.lessonId = lessonId
    record.exerciseKind = kind.rawValue
    record.cpm = cpm
    return record
}

/// Звёзды проверок этапов: лучшая завершённая проверка этапа своего языка; шаги других видов, брошенные попытки и
/// чужой язык не в счёт. Цель проверки этапа 1 — «до» (80 зн/мин): 70 зн/мин при точности 99% — ★★.
@MainActor @Test func stageCheckStarsComeFromTheBestCompletedCheck() throws {
    let container = try makeContainer()
    defer { withExtendedLifetime(container) {} }
    let context = container.mainContext
    let course = try CourseFixtureApp.ruMini()
    context.insert(courseStep("ru2.s1.check", kind: .check, cpm: 70))
    context.insert(courseStep("ru2.s1.check", kind: .check, cpm: 50))
    // Ни звёзд, ни зачёта: брошенная проверка, быстрый шаг не-проверка, чужой язык.
    context.insert(courseStep("ru2.s1.check", kind: .check, cpm: 200, completed: false))
    context.insert(courseStep("ru2.s1.check", kind: .words, cpm: 200))
    context.insert(courseStep("ru2.s1.check", kind: .check, language: .en, cpm: 200))
    let stars = try ProgressSnapshot(context: context).stageCheckStars(course: course)
    #expect(stars == ["ru2.s1.check": 2])
}

@MainActor @Test func stageCheckStarsAreEmptyWithoutAttempts() throws {
    let container = try makeContainer()
    defer { withExtendedLifetime(container) {} }
    let course = try CourseFixtureApp.ruMini()
    #expect(try ProgressSnapshot(context: container.mainContext).stageCheckStars(course: course).isEmpty)
}

/// Выборка по языку: сессии другого языка не читаются.
@MainActor @Test func sessionSummariesByLanguageSkipOtherLanguages() throws {
    let container = try makeContainer()
    defer { withExtendedLifetime(container) {} }
    let context = container.mainContext
    context.insert(courseStep("ru2.s1.01", kind: .check, cpm: 100))
    context.insert(courseStep("en2.s1.01", kind: .check, language: .en, cpm: 300))
    let snapshot = ProgressSnapshot(context: context)
    #expect(try snapshot.sessionSummaries(language: .ru).map(\.language) == [.ru])
    #expect(try snapshot.sessionSummaries(language: .en).map(\.language) == [.en])
}

/// Ориентир «Ускорения» русского курса не зависит от проверок английского: без «Ускорения» это средняя
/// последних проверок курса, и быстрые английские проверки её не сдвигают.
@MainActor @Test func englishChecksDoNotChangeTheRussianSpeedupReference() throws {
    let container = try makeContainer()
    defer { withExtendedLifetime(container) {} }
    let context = container.mainContext
    let course = try CourseFixtureApp.ruMini()
    let snapshot = ProgressSnapshot(context: context)
    #expect(try snapshot.speedupReference(course: course) == nil)
    context.insert(courseStep("ru2.s1.check", kind: .check, cpm: 100, endedAt: noon))
    context.insert(courseStep("ru2.s1.01", kind: .check, cpm: 120, endedAt: noon.addingTimeInterval(60)))
    let before = try snapshot.speedupReference(course: course)
    #expect(before == 110)
    context.insert(courseStep("en2.s1.check", kind: .check, language: .en, cpm: 400, endedAt: noon.addingTimeInterval(120)))
    context.insert(courseStep("en2.s2.02", kind: .check, language: .en, cpm: 500, endedAt: noon.addingTimeInterval(180)))
    #expect(try snapshot.speedupReference(course: course) == before)
}

@MainActor @Test func keyStatsAreFilteredByLanguage() throws {
    let container = try makeContainer()
    defer { withExtendedLifetime(container) {} }
    let context = container.mainContext
    let ru = KeyStat(language: "ru", character: "а")
    ru.keyCode = 0; ru.presses = 10; ru.errors = 2; ru.ewmaMs = 250
    let en = KeyStat(language: "en", character: "a")
    en.keyCode = 0; en.presses = 99
    context.insert(ru)
    context.insert(en)
    let stats = try ProgressSnapshot(context: context).keyStats(language: .ru)
    #expect(stats == [KeyStatSummary(keyCode: 0, presses: 10, errors: 2, ewmaMs: 250)])
}

@MainActor @Test func streakUsesLogicalTodayKey() throws {
    let container = try makeContainer()
    defer { withExtendedLifetime(container) {} }
    let context = container.mainContext
    // Вчера и позавчера — полные дни (цель 10 минут), сегодня половинный.
    context.insert(day("2026-03-08", seconds: 700, completed: 2))
    context.insert(day("2026-03-09", seconds: 700, completed: 2))
    context.insert(day("2026-03-10", seconds: 60, completed: 1))
    let snapshot = ProgressSnapshot(context: context)
    let summary = try snapshot.streak(goalSeconds: 600, dayStartHour: 4, now: noon, calendar: utc())
    #expect(summary.current == 3)
    #expect(summary.today == .half)
    #expect(summary.fullInCurrent == 2)

    // В 02:00 логический день ещё прежний: «сегодня» — 2026-03-09, и 03-10 в серию не входит.
    let night = Date(timeIntervalSince1970: 1_773_144_000 - 10 * 3600)
    let early = try snapshot.streak(goalSeconds: 600, dayStartHour: 4, now: night, calendar: utc())
    #expect(early.today == .full)
    #expect(early.current == 2)
}

@MainActor @Test func emptyStoreGivesEmptyStreak() throws {
    let container = try makeContainer()
    defer { withExtendedLifetime(container) {} }
    let summary = try ProgressSnapshot(context: container.mainContext).streak(goalSeconds: 600, dayStartHour: 4, now: noon, calendar: utc())
    #expect(summary.current == 0)
    #expect(summary.today == DayStatus.none)
}

/// Главная читает только сессии последней недели и одну — самую раннюю — для даты первого занятия.
@MainActor @Test func sessionWindowAndFirstSessionDate() throws {
    let container = try makeContainer()
    defer { withExtendedLifetime(container) {} }
    let context = container.mainContext
    context.insert(session(day: "2026-01-02", endedAt: noon.addingTimeInterval(-60 * 86_400)))
    context.insert(session(day: "2026-03-03", endedAt: noon.addingTimeInterval(-7 * 86_400)))
    context.insert(session(day: "2026-03-04", endedAt: noon.addingTimeInterval(-6 * 86_400)))
    context.insert(session(day: "2026-03-10", language: .en))
    let snapshot = ProgressSnapshot(context: context)
    #expect(try snapshot.sessionSummaries(fromDay: "2026-03-04").map(\.day).sorted() == ["2026-03-04", "2026-03-10"])
    #expect(try snapshot.firstSessionDate() == noon.addingTimeInterval(-60 * 86_400))
    #expect(try snapshot.firstSessionDate(language: .en) == noon)
    let empty = try makeContainer()
    defer { withExtendedLifetime(empty) {} }
    #expect(try ProgressSnapshot(context: empty.mainContext).firstSessionDate() == nil)
}
