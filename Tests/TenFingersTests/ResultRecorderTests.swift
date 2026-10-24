import Foundation
import SwiftData
import Testing
import TypingCore
@testable import TenFingers

private func result(at date: Date, completed: Bool = true, lessonId: String? = "ru.1.1") -> ExerciseResult {
    var engine = TypingEngine(text: "ао")
    _ = engine.handle(Keystroke(character: "а", keyCode: 3, timestamp: 0))
    if completed {
        _ = engine.handle(Keystroke(character: "x", keyCode: 7, timestamp: 0.2))
        _ = engine.handle(Keystroke(character: "о", keyCode: 38, timestamp: 0.5))
    }
    return ExerciseResult(engine: engine, mode: .course, language: .ru, lessonId: lessonId,
                          startedAt: date, endedAt: date, hintLevel: .full)
}

private func date(_ day: Int, _ hour: Int) -> Date {
    Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour))!
}

@MainActor @Test func sameLogicalDayIsAggregated() throws {
    let container = try ModelStore.makeContainer(inMemory: true)
    let recorder = ResultRecorder(context: container.mainContext, dayStartHour: 4)
    try recorder.commit { try recorder.record(result(at: date(23, 20))) }
    try recorder.commit { try recorder.record(result(at: date(24, 2))) } // ещё 23-е
    try recorder.commit { try recorder.record(result(at: date(24, 3), completed: false)) } // брошено
    let days = try container.mainContext.fetch(FetchDescriptor<DayRecord>())
    #expect(days.count == 1)
    #expect(days[0].logicalDay == "2026-10-23")
    #expect(days[0].completedExercises == 2)
    #expect(days[0].abandonedExercises == 1)
    #expect(days[0].languages == ["ru"])
    #expect(try container.mainContext.fetchCount(FetchDescriptor<SessionRecord>()) == 3)
}

@MainActor @Test func keyStatsAccumulate() throws {
    let container = try ModelStore.makeContainer(inMemory: true)
    let recorder = ResultRecorder(context: container.mainContext, dayStartHour: 4)
    try recorder.commit { try recorder.record(result(at: date(23, 12))) }
    try recorder.commit { try recorder.record(result(at: date(23, 13))) }
    let stats = try container.mainContext.fetch(FetchDescriptor<KeyStat>())
    let o = try #require(stats.first { $0.character == "о" })
    #expect(o.presses == 2)
    #expect(o.errors == 2)
    #expect(o.ewmaMs == 500)
    #expect(o.recent == [true, true])
    #expect(o.keyCode == 38)
}

@MainActor @Test func bigramStatsAccumulate() throws {
    let container = try ModelStore.makeContainer(inMemory: true)
    let recorder = ResultRecorder(context: container.mainContext, dayStartHour: 4)
    try recorder.commit { try recorder.record(result(at: date(23, 12))) }
    try recorder.commit { try recorder.record(result(at: date(23, 13))) }
    let stats = try container.mainContext.fetch(FetchDescriptor<BigramStat>())
    #expect(stats.count == 1)
    let ao = try #require(stats.first)
    #expect(ao.bigram == "ао")
    #expect(ao.language == "ru")
    #expect(ao.count == 2)
    #expect(ao.errors == 2)
    #expect(ao.recent == [true, true])
    #expect(ao.ewmaMs == 500)
}

@MainActor @Test func lessonProgressKeepsBestAndPassDate() throws {
    let container = try ModelStore.makeContainer(inMemory: true)
    let recorder = ResultRecorder(context: container.mainContext, dayStartHour: 4)
    try recorder.commit { try recorder.recordLesson(result(at: date(23, 12)), stars: 0) }
    try recorder.commit { try recorder.recordLesson(result(at: date(23, 13)), stars: 2) }
    try recorder.commit { try recorder.recordLesson(result(at: date(23, 14)), stars: 1) }
    let progress = try #require(try container.mainContext.fetch(FetchDescriptor<LessonProgress>()).first)
    #expect(progress.attempts == 3)
    #expect(progress.bestStars == 2)
    #expect(progress.passedAt == date(23, 13))
}

@MainActor @Test func countersIncrement() throws {
    let container = try ModelStore.makeContainer(inMemory: true)
    let recorder = ResultRecorder(context: container.mainContext, dayStartHour: 4)
    try recorder.commit { try recorder.increment(CounterName.wrongLayoutStarts) }
    try recorder.commit { try recorder.increment(CounterName.wrongLayoutStarts) }
    let counter = try #require(try container.mainContext.fetch(FetchDescriptor<CounterRecord>()).first)
    #expect(counter.value == 2)
}

private struct Boom: Error {}

@MainActor @Test func failedCommitPersistsNothing() throws {
    let container = try ModelStore.makeContainer(inMemory: true)
    let recorder = ResultRecorder(context: container.mainContext, dayStartHour: 4)
    #expect(throws: Boom.self) {
        try recorder.commit {
            try recorder.record(result(at: date(23, 12)))
            try recorder.increment(CounterName.capsLockPresses)
            throw Boom()
        }
    }
    #expect(try container.mainContext.fetchCount(FetchDescriptor<SessionRecord>()) == 0)
    #expect(try container.mainContext.fetchCount(FetchDescriptor<DayRecord>()) == 0)
    #expect(try container.mainContext.fetchCount(FetchDescriptor<KeyStat>()) == 0)
    #expect(try container.mainContext.fetchCount(FetchDescriptor<CounterRecord>()) == 0)
}

@MainActor @Test func sessionStoresExerciseKindAndPinkyCounts() throws {
    let container = try ModelStore.makeContainer(inMemory: true)
    let recorder = ResultRecorder(context: container.mainContext, dayStartHour: 4)
    // ф (0, левый мизинец) с ошибкой, ж (41, правый мизинец) без ошибки
    var engine = TypingEngine(text: "фж")
    _ = engine.handle(Keystroke(character: "x", keyCode: 7, timestamp: 0))
    _ = engine.handle(Keystroke(character: "ф", keyCode: 0, timestamp: 0.1))
    _ = engine.handle(Keystroke(character: "ж", keyCode: 41, timestamp: 0.3))
    let checked = ExerciseResult(engine: engine, mode: .course, language: .ru, lessonId: "ru.1.4",
                                 startedAt: date(23, 12), endedAt: date(23, 12), hintLevel: .full,
                                 exerciseKind: .check)
    try recorder.commit {
        try recorder.record(checked)
        try recorder.record(result(at: date(23, 13)))
    }
    let sessions = try container.mainContext.fetch(
        FetchDescriptor<SessionRecord>(sortBy: [SortDescriptor(\.startedAt)]))
    #expect(sessions.count == 2)
    #expect(sessions[0].exerciseKind == "check")
    #expect(sessions[0].pinkyPresses == 2)
    #expect(sessions[0].pinkyErrors == 1)
    #expect(sessions[1].exerciseKind == nil)
    #expect(sessions[1].pinkyPresses == 0)
    #expect(sessions[1].pinkyErrors == 0)
}

/// Час начала дня читается при каждой записи: смена настройки посреди запуска действует сразу.
@MainActor @Test func dayStartHourIsReadAtCommitTime() throws {
    let (defaults, name) = makeTestDefaults("ResultRecorderTests-")
    defer { removeTestDefaults(name) }
    defaults.set(4, forKey: SettingsKey.dayStartHour)
    let container = try ModelStore.makeContainer(inMemory: true)
    let recorder = ResultRecorder(context: container.mainContext,
                                  dayStartHour: { StoredSettings.dayStartHour(defaults) })
    try recorder.commit { try recorder.record(result(at: date(24, 3))) }  // до 4:00 — ещё 23-е
    defaults.set(0, forKey: SettingsKey.dayStartHour)
    try recorder.commit { try recorder.record(result(at: date(24, 3))) }  // день с полуночи — уже 24-е
    let days = try container.mainContext.fetch(FetchDescriptor<DayRecord>()).map(\.logicalDay).sorted()
    #expect(days == ["2026-10-23", "2026-10-24"])
}

@Test func storedDayStartHourFallsBackToDefault() throws {
    let (defaults, name) = makeTestDefaults("ResultRecorderTests-")
    defer { removeTestDefaults(name) }
    #expect(StoredSettings.dayStartHour(defaults) == SettingsDefault.dayStartHour)
    defaults.set(2, forKey: SettingsKey.dayStartHour)
    #expect(StoredSettings.dayStartHour(defaults) == 2)
}

/// Сессия хранит нажатия и ошибки по пальцам и число «ё» без ошибки (фаза 5, поколение схемы 4).
@MainActor @Test func sessionStoresFingerCountsAndYo() throws {
    let container = try ModelStore.makeContainer(inMemory: true)
    let recorder = ResultRecorder(context: container.mainContext, dayStartHour: 4)
    var engine = TypingEngine(text: "ёа о")
    let keys: [(Character, UInt16, Double)] = [("ё", 50, 0), ("а", 3, 0.2), (" ", 49, 0.3), ("x", 7, 0.4), ("о", 38, 0.5)]
    for (c, code, t) in keys { _ = engine.handle(Keystroke(character: c, keyCode: code, timestamp: t)) }
    let typed = ExerciseResult(engine: engine, mode: .practice, language: .ru, lessonId: nil,
                                startedAt: date(23, 12), endedAt: date(23, 12), hintLevel: .full)
    try recorder.commit { try recorder.record(typed, source: "words") }
    let session = try #require(try container.mainContext.fetch(FetchDescriptor<SessionRecord>()).first)
    let expected = KeyStats.fingerCounts(from: typed)
    #expect(FingerCounts.counts(session.fingerPresses) == expected.presses)
    #expect(FingerCounts.counts(session.fingerErrors) == expected.errors)
    #expect(FingerCounts.counts(session.fingerPresses)?[.thumb] == 1)
    #expect(FingerCounts.counts(session.fingerErrors)?[FingerMap.finger(for: 38)!] == 1)
    #expect(session.yoPresses == 1)

    // Английская сессия: «ё» нет — 0, а не nil.
    try recorder.commit { try recorder.record(result(at: date(23, 13))) }
    let english = ExerciseResult(engine: TypingEngine(text: "a"), mode: .practice, language: .en, lessonId: nil,
                                 startedAt: date(23, 14), endedAt: date(23, 14), hintLevel: .full)
    try recorder.commit { try recorder.record(english) }
    let last = try #require(try container.mainContext.fetch(
        FetchDescriptor<SessionRecord>(sortBy: [SortDescriptor(\.endedAt)])).last)
    #expect(last.language == "en" && last.yoPresses == 0)
    #expect(FingerCounts.counts(last.fingerPresses) == [:])
}
