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
    try recorder.commit { try recorder.recordLesson(result(at: date(23, 13)), stars: 4) }
    try recorder.commit { try recorder.recordLesson(result(at: date(23, 14)), stars: 2) }
    let progress = try #require(try container.mainContext.fetch(FetchDescriptor<LessonProgress>()).first)
    #expect(progress.attempts == 3)
    #expect(progress.bestStars == 3) // ★★★★ новой шкалы — прежние 3
    #expect(progress.passedAt == date(23, 13))
}

/// Уроки издания 1 хранят `bestStars` в прежней 3-звёздной шкале: 5 → 3, 3 → 2, 2 → 1.
@MainActor @Test func lessonProgressStoresLegacyScale() throws {
    for (stars, legacy) in [(5, 3), (3, 2), (2, 1)] {
        let container = try ModelStore.makeContainer(inMemory: true)
        let recorder = ResultRecorder(context: container.mainContext, dayStartHour: 4)
        try recorder.commit { try recorder.recordLesson(result(at: date(23, 12)), stars: stars) }
        let progress = try #require(try container.mainContext.fetch(FetchDescriptor<LessonProgress>()).first)
        #expect(progress.bestStars == legacy, "\(stars)")
        #expect(progress.passedAt == date(23, 12))
    }
}

/// Уроки издания 2 хранят `bestStars` в 5-звёздной шкале как есть.
@MainActor @Test func lessonProgressStoresFiveStarScaleForEditionTwo() throws {
    let container = try ModelStore.makeContainer(inMemory: true)
    let recorder = ResultRecorder(context: container.mainContext, dayStartHour: 4)
    try recorder.commit { try recorder.recordLesson(result(at: date(23, 12), lessonId: "ru2.s1.01"), stars: 5) }
    let progress = try #require(try container.mainContext.fetch(FetchDescriptor<LessonProgress>()).first)
    #expect(progress.lessonId == "ru2.s1.01" && progress.bestStars == 5)
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

private func textResult(_ text: String, typed: Int? = nil, mode: ExerciseMode = .practice, lessonId: String? = nil,
                        stepIndex: Int? = nil, connected: Bool = false) -> ExerciseResult {
    var engine = TypingEngine(text: text)
    for (index, character) in text.prefix(typed ?? text.count).enumerated() {
        _ = engine.handle(Keystroke(character: character, keyCode: 3, timestamp: Double(index)))
    }
    return ExerciseResult(engine: engine, mode: mode, language: .ru, lessonId: lessonId,
                          startedAt: .now, endedAt: .now, hintLevel: .full, stepIndex: stepIndex,
                          connected: connected)
}

@MainActor @Test func courseSessionStoresStepIndexAndTraits() throws {
    let container = try ModelStore.makeContainer(inMemory: true)
    let recorder = ResultRecorder(context: container.mainContext, dayStartHour: 4)
    try recorder.commit {
        try recorder.record(textResult("ао", mode: .course, lessonId: "ru.1.1", stepIndex: 2))
    }
    let session = try #require(try container.mainContext.fetch(FetchDescriptor<SessionRecord>()).first)
    #expect(session.stepIndex == 2)
    #expect(session.textTraits == 0)
    #expect(session.planSlot == nil)
}

@MainActor @Test func courseConnectedTextStoresTraitAndStepIndex() throws {
    let container = try ModelStore.makeContainer(inMemory: true)
    let recorder = ResultRecorder(context: container.mainContext, dayStartHour: 4)
    try recorder.commit {
        try recorder.record(textResult("ао", mode: .course, lessonId: "ru2.s1.01", stepIndex: 4, connected: true))
    }
    let session = try #require(try container.mainContext.fetch(FetchDescriptor<SessionRecord>()).first)
    #expect((session.textTraits ?? 0) & 8 != 0)
    #expect(session.stepIndex == 4)
}

@MainActor @Test func practiceFromLibraryStoresConnectedTrait() throws {
    let container = try ModelStore.makeContainer(inMemory: true)
    let recorder = ResultRecorder(context: container.mainContext, dayStartHour: 4)
    try recorder.commit { try recorder.record(textResult("Да"), source: "library:x") }
    let session = try #require(try container.mainContext.fetch(FetchDescriptor<SessionRecord>()).first)
    #expect(session.textTraits == 9)
    #expect(session.stepIndex == nil)
}

@MainActor @Test func abandonedExerciseStillStoresTextTraits() throws {
    let container = try ModelStore.makeContainer(inMemory: true)
    let recorder = ResultRecorder(context: container.mainContext, dayStartHour: 4)
    try recorder.commit { try recorder.record(textResult("Да, 2", typed: 1)) }
    let session = try #require(try container.mainContext.fetch(FetchDescriptor<SessionRecord>()).first)
    #expect(!session.completed)
    #expect(session.textTraits == 7)
}

/// «Освежить»: сессия курса вида `refresh` с номером проверки; `recordLesson` засчитывает звёзды, как повтор проверки.
@MainActor @Test func refreshIsRecordedAsCourseExerciseWithCheckStepIndex() throws {
    let container = try ModelStore.makeContainer(inMemory: true)
    let recorder = ResultRecorder(context: container.mainContext, dayStartHour: 4)
    var engine = TypingEngine(text: "ао")
    _ = engine.handle(Keystroke(character: "а", keyCode: 3, timestamp: 0))
    _ = engine.handle(Keystroke(character: "о", keyCode: 38, timestamp: 0.4))
    let refreshed = ExerciseResult(engine: engine, mode: .course, language: .ru, lessonId: "ru2.s1.01",
                                   startedAt: date(23, 12), endedAt: date(23, 12), hintLevel: .full,
                                   exerciseKind: .refresh, stepIndex: 5)
    try recorder.commit {
        try recorder.record(refreshed)
        try recorder.recordLesson(refreshed, stars: 3)
    }
    let session = try #require(try container.mainContext.fetch(FetchDescriptor<SessionRecord>()).first)
    #expect(session.mode == "course" && session.exerciseKind == "refresh" && session.stepIndex == 5)
    #expect(session.lessonId == "ru2.s1.01")
    #expect(try container.mainContext.fetch(FetchDescriptor<LessonProgress>()).first?.bestStars == 3)
}

/// Пункт плана пишется строкой `PlanSlot.rawValue` и читается обратно в `SessionSummary.planSlot`; без него — `nil`.
@MainActor @Test func planSlotIsStoredAndReadIntoSummary() throws {
    let container = try ModelStore.makeContainer(inMemory: true)
    let recorder = ResultRecorder(context: container.mainContext, dayStartHour: 4)
    try recorder.commit {
        try recorder.record(textResult("ао"), source: "plan:text", planSlot: .training)
        try recorder.record(textResult("оа", mode: .course, lessonId: "ru.1.1", stepIndex: 1))
    }
    let records = try container.mainContext.fetch(FetchDescriptor<SessionRecord>())
    #expect(Set(records.map(\.planSlot)) == ["training", nil])
    let summaries = try ProgressSnapshot(context: container.mainContext).sessionSummaries()
    #expect(summaries.first { $0.mode == .practice }?.planSlot == .training)
    #expect(summaries.first { $0.mode == .course }?.planSlot == nil)
}

private func longResult(mode: ExerciseMode, completed: Bool = true) -> ExerciseResult {
    let text = String(repeating: "слово ", count: 10)   // 60 знаков
    var engine = TypingEngine(text: text)
    var clock = 0.0
    for character in text {
        clock += 0.2
        _ = engine.handle(Keystroke(character: character, keyCode: 3, timestamp: clock))
    }
    let at = Date(timeIntervalSince1970: 1_800_000_000)
    return ExerciseResult(engine: engine, mode: mode, language: .ru, lessonId: mode == .course ? "ru.1.1" : nil,
                          startedAt: at, endedAt: at, hintLevel: .full)
}

/// Отрезки скорости пишутся только для курса; у тренировок и практики поле пустое.
@MainActor @Test func speedSegmentsAreRecordedForCourseOnly() throws {
    let container = try ModelStore.makeContainer(inMemory: true)
    let recorder = ResultRecorder(context: container.mainContext, dayStartHour: 4)
    try recorder.commit {
        try recorder.record(longResult(mode: .course))
        try recorder.record(longResult(mode: .adaptive))
        try recorder.record(longResult(mode: .practice))
        try recorder.record(longResult(mode: .weak))
    }
    let sessions = try container.mainContext.fetch(FetchDescriptor<SessionRecord>())
    let course = try #require(sessions.first { $0.mode == "course" })
    let segments = try #require(course.decodedSpeedSegments)
    #expect(segments == SpeedSegments.split(text: String(repeating: "слово ", count: 10),
                                            timings: longResult(mode: .course).timings))
    #expect(segments.count >= 2 && segments.first?.start == 0 && segments.last?.end == 60)
    #expect(sessions.filter { $0.mode != "course" }.allSatisfy { $0.speedSegments == nil })
}

// MARK: - Слова с ошибками (поколение 9)

/// Набор текста целиком; перед символами из `wrongAt` (позиции в тексте) нажимается неверная клавиша.
private func typed(_ text: String, wrongAt: Set<Int> = [], mode: ExerciseMode = .practice,
                   completed: Bool = true, language: Language = .ru, lessonId: String? = nil,
                   at date: Date) -> ExerciseResult {
    var engine = TypingEngine(text: text)
    var time = 0.0
    for (index, character) in text.enumerated() {
        if !completed && index == text.count - 1 { break }
        if wrongAt.contains(index) {
            time += 0.2
            _ = engine.handle(Keystroke(character: "~", keyCode: 50, timestamp: time))
        }
        time += 0.2
        _ = engine.handle(Keystroke(character: character, keyCode: 4, timestamp: time))
    }
    return ExerciseResult(engine: engine, mode: mode, language: language, lessonId: lessonId,
                          startedAt: date, endedAt: date, hintLevel: .full)
}

@MainActor @Test func errorsInTextAreStoredAsErrorWords() throws {
    let container = try ModelStore.makeContainer(inMemory: true)
    let recorder = ResultRecorder(context: container.mainContext, dayStartHour: 4)
    // «Привет» (позиция 0) и «мир» (позиция 7) с ошибками, «да» — чисто, «я» — короче двух букв, «дсэо» — не слово.
    try recorder.commit {
        try recorder.record(typed("Привет мир да я дсэо", wrongAt: [0, 7, 16], at: date(23, 12)))
    }
    let words = try container.mainContext.fetch(FetchDescriptor<ErrorWord>(sortBy: [SortDescriptor(\.text)]))
    #expect(words.map(\.text) == ["мир", "привет"])
    #expect(words.allSatisfy { !$0.isPhrase })
    #expect(words.allSatisfy { $0.language == "ru" && $0.errors == 1 && $0.cleanStreak == 0 })
}

/// Урок курса, где вводится апостроф, — первый урок английского курса с `'` среди новых клавиш.
private func apostropheLesson() throws -> (id: String, before: String) {
    let lessons = try CourseCatalog.load(.en).lessons
    let index = try #require(lessons.firstIndex { $0.newCharacters.contains("'") })
    return (lessons[index].id, lessons[index - 1].id)
}

@MainActor @Test func contractionIsNotStoredBeforeApostropheLesson() throws {
    let container = try ModelStore.makeContainer(inMemory: true)
    let context = container.mainContext
    let lesson = try apostropheLesson()
    context.insert(LessonProgress(lessonId: lesson.before, language: "en"))
    try context.fetch(FetchDescriptor<LessonProgress>()).first?.passedAt = date(22, 12)
    let recorder = ResultRecorder(context: context, dayStartHour: 4)
    // Ошибка в «don't» (позиция 2) — апостроф ещё не знаком: в список не попадает.
    try recorder.commit { try recorder.record(typed("I don't know", wrongAt: [2], language: .en, at: date(23, 12))) }
    #expect(try context.fetchCount(FetchDescriptor<ErrorWord>()) == 0)
}

@MainActor @Test func contractionIsStoredWholeAfterApostropheLesson() throws {
    let container = try ModelStore.makeContainer(inMemory: true)
    let context = container.mainContext
    let lesson = try apostropheLesson()
    context.insert(LessonProgress(lessonId: lesson.id, language: "en"))
    try context.fetch(FetchDescriptor<LessonProgress>()).first?.passedAt = date(22, 12)
    let recorder = ResultRecorder(context: context, dayStartHour: 4)
    try recorder.commit { try recorder.record(typed("I don't know", wrongAt: [2], language: .en, at: date(23, 12))) }
    #expect(try context.fetch(FetchDescriptor<ErrorWord>()).map(\.text) == ["don't"])
}

@MainActor @Test func contractionIsStoredInTheApostropheLessonItself() throws {
    let container = try ModelStore.makeContainer(inMemory: true)
    let context = container.mainContext
    let lesson = try apostropheLesson()
    let recorder = ResultRecorder(context: context, dayStartHour: 4)
    try recorder.commit {
        try recorder.record(typed("I can't stop", wrongAt: [5], mode: .course, language: .en, lessonId: lesson.id,
                                  at: date(23, 12)))
    }
    #expect(try context.fetch(FetchDescriptor<ErrorWord>()).map(\.text) == ["can't"])
}

@MainActor @Test func abandonedExerciseDoesNotStoreErrorWords() throws {
    let container = try ModelStore.makeContainer(inMemory: true)
    let recorder = ResultRecorder(context: container.mainContext, dayStartHour: 4)
    try recorder.commit {
        try recorder.record(typed("Привет мир", wrongAt: [0], completed: false, at: date(23, 12)))
    }
    #expect(try container.mainContext.fetchCount(FetchDescriptor<ErrorWord>()) == 0)
}

@MainActor @Test func rhythmModeDoesNotStoreErrorWords() throws {
    let container = try ModelStore.makeContainer(inMemory: true)
    let recorder = ResultRecorder(context: container.mainContext, dayStartHour: 4)
    try recorder.commit {
        try recorder.record(typed("Привет мир", wrongAt: [0], mode: .rhythm, at: date(23, 12)))
    }
    #expect(try container.mainContext.fetchCount(FetchDescriptor<ErrorWord>()) == 0)
}

@MainActor @Test func threeCleanRunsRemoveWordAndCountFixed() throws {
    let container = try ModelStore.makeContainer(inMemory: true)
    let context = container.mainContext
    let recorder = ResultRecorder(context: context, dayStartHour: 4)
    try recorder.commit { try recorder.record(typed("привет", wrongAt: [0], at: date(23, 12))) }
    #expect(try context.fetchCount(FetchDescriptor<ErrorWord>()) == 1)
    for hour in 13...14 {
        try recorder.commit { try recorder.record(typed("Привет", at: date(23, hour))) }
    }
    #expect(try context.fetch(FetchDescriptor<ErrorWord>()).first?.cleanStreak == 2)
    #expect(try StatsReader(context: context).fixedWords() == 0)
    try recorder.commit { try recorder.record(typed("привет", at: date(23, 15))) }
    #expect(try context.fetchCount(FetchDescriptor<ErrorWord>()) == 0)
    #expect(try StatsReader(context: context).fixedWords() == 1)
    let counters = try context.fetch(FetchDescriptor<CounterRecord>())
    #expect(counters.first { $0.name == "fixedWords" }?.value == 1)
}

@MainActor @Test func statsReaderReadsLanguageErrorWords() throws {
    let container = try ModelStore.makeContainer(inMemory: true)
    let context = container.mainContext
    let now = date(23, 12)
    context.insert(ErrorWord(language: "ru", text: "привет", isPhrase: false, errors: 3, cleanStreak: 1,
                             firstSeen: now, lastSeen: now))
    context.insert(ErrorWord(language: "en", text: "hello", isPhrase: false, errors: 1, cleanStreak: 0,
                             firstSeen: now, lastSeen: now))
    try context.save()
    let reader = StatsReader(context: context)
    #expect(try reader.errorWords(language: .ru) == [
        ErrorWordEntry(text: "привет", isPhrase: false, errors: 3, cleanStreak: 1, firstSeen: now, lastSeen: now)])
    #expect(try reader.errorWords(language: .en).map(\.text) == ["hello"])
    #expect(try reader.fixedWords() == 0)
}

@MainActor @Test func duplicateErrorWordsInStoreCollapseToOne() throws {
    let container = try ModelStore.makeContainer(inMemory: true)
    let context = container.mainContext
    let recorder = ResultRecorder(context: context, dayStartHour: 4)
    let seen = date(22, 12)
    for _ in 0..<2 {
        context.insert(ErrorWord(language: "ru", text: "привет", isPhrase: false, errors: 1, cleanStreak: 0,
                                 firstSeen: seen, lastSeen: seen))
    }
    try context.save()
    try recorder.commit { try recorder.record(typed("привет", wrongAt: [0], at: date(23, 12))) }
    let words = try context.fetch(FetchDescriptor<ErrorWord>())
    #expect(words.count == 1)
    #expect(words.first?.errors == 2)
}

@MainActor @Test func threeCleanOccurrencesInOneExerciseFixWord() throws {
    let container = try ModelStore.makeContainer(inMemory: true)
    let context = container.mainContext
    let recorder = ResultRecorder(context: context, dayStartHour: 4)
    try recorder.commit { try recorder.record(typed("привет", wrongAt: [0], at: date(23, 12))) }
    try recorder.commit { try recorder.record(typed("привет привет привет", at: date(23, 13))) }
    #expect(try context.fetchCount(FetchDescriptor<ErrorWord>()) == 0)
    #expect(try StatsReader(context: context).fixedWords() == 1)
}

@MainActor @Test func recordingCleansPhrasesAndNonWordsWithoutCountingFixed() throws {
    let container = try ModelStore.makeContainer(inMemory: true)
    let context = container.mainContext
    let seen = date(22, 12)
    for (text, phrase) in [("бт", false), ("бт сделает", true), ("привет мир", true), ("привет", false)] {
        context.insert(ErrorWord(language: "ru", text: text, isPhrase: phrase, errors: 1, cleanStreak: 2,
                                 firstSeen: seen, lastSeen: seen))
    }
    context.insert(ErrorWord(language: "en", text: "бт", isPhrase: false, errors: 1, cleanStreak: 0,
                             firstSeen: seen, lastSeen: seen))
    try context.save()
    let recorder = ResultRecorder(context: context, dayStartHour: 4)
    try recorder.commit { try recorder.record(typed("мир", wrongAt: [0], at: date(23, 12))) }
    let ru = try context.fetch(FetchDescriptor<ErrorWord>(sortBy: [SortDescriptor(\.text)])).filter { $0.language == "ru" }
    #expect(ru.map(\.text) == ["мир", "привет"])
    #expect(try context.fetchCount(FetchDescriptor<ErrorWord>()) == 3)   // запись другого языка не тронута
    #expect(try StatsReader(context: context).fixedWords() == 0)
}

@MainActor @Test func statsReaderHidesPhrasesAndNonWords() throws {
    let container = try ModelStore.makeContainer(inMemory: true)
    let context = container.mainContext
    let now = date(23, 12)
    for (text, phrase) in [("бт", false), ("бт сделает", true), ("привет мир", true), ("привет", false), ("дсэо", false)] {
        context.insert(ErrorWord(language: "ru", text: text, isPhrase: phrase, errors: 1, cleanStreak: 0,
                                 firstSeen: now, lastSeen: now))
    }
    try context.save()
    #expect(try StatsReader(context: context).errorWords(language: .ru).map(\.text) == ["привет"])
    #expect(try context.fetchCount(FetchDescriptor<ErrorWord>()) == 5)   // читатель ничего не удаляет
}

@MainActor @Test func emptyVocabularyLeavesErrorWordsUntouched() throws {
    let container = try ModelStore.makeContainer(inMemory: true)
    let context = container.mainContext
    let seen = date(22, 12)
    context.insert(ErrorWord(language: "ru", text: "привет", isPhrase: false, errors: 1, cleanStreak: 0,
                             firstSeen: seen, lastSeen: seen))
    try context.save()
    var recorder = ResultRecorder(context: context, dayStartHour: 4)
    recorder.vocabulary = { _ in [] }
    try recorder.commit { try recorder.record(typed("мир", wrongAt: [0], at: date(23, 12))) }
    #expect(try context.fetch(FetchDescriptor<ErrorWord>()).map(\.text) == ["привет"])
    var reader = StatsReader(context: context)
    reader.vocabulary = { _ in [] }
    #expect(try reader.errorWords(language: .ru).map(\.text) == ["привет"])
}

// MARK: - Замер скорости

private func measureResult(at date: Date, cpmTarget: String = "ао") -> ExerciseResult {
    var engine = TypingEngine(text: cpmTarget)
    _ = engine.handle(Keystroke(character: "а", keyCode: 3, timestamp: 0))
    _ = engine.handle(Keystroke(character: "о", keyCode: 38, timestamp: 0.5))
    return ExerciseResult(engine: engine, mode: .measure, language: .ru, lessonId: nil,
                          startedAt: date, endedAt: date, hintLevel: .hidden)
}

@MainActor @Test func measurementIsRecordedAsSessionDayAndKeyStats() throws {
    let container = try ModelStore.makeContainer(inMemory: true)
    let context = container.mainContext
    let recorder = ResultRecorder(context: context, dayStartHour: 4)
    let variant = MeasureVariant(duration: .seconds(60), kind: .plain, language: .ru)
    let replay = MeasureReplay(text: "ао", keys: [ReplayKey(position: 0, typed: "а", offsetMs: 0)])
    try recorder.commit { try recorder.recordMeasurement(measureResult(at: date(23, 12)), variant: variant, replay: replay) }

    let session = try #require(try context.fetch(FetchDescriptor<SessionRecord>()).first)
    #expect(session.mode == "measure" && session.completed && session.source == "measure:60:plain:ru")
    let day = try #require(try context.fetch(FetchDescriptor<DayRecord>()).first)
    #expect(day.logicalDay == "2026-10-23" && day.completedExercises == 1 && day.activeSeconds > 0)
    #expect(try context.fetch(FetchDescriptor<KeyStat>()).contains { $0.character == "о" && $0.presses == 1 })
    let saved = try #require(try context.fetch(FetchDescriptor<SpeedMeasurement>()).first)
    #expect(saved.duration == "60" && saved.textKind == "plain" && saved.language == "ru")
    #expect(saved.chars == 2 && saved.errors == 0 && saved.cpm == session.cpm)
    #expect(MeasureReplay(data: try #require(saved.replay)) == replay)
}

@MainActor @Test func seventhMeasurementOfVariantRemovesSecondByDate() throws {
    let container = try ModelStore.makeContainer(inMemory: true)
    let context = container.mainContext
    let recorder = ResultRecorder(context: context, dayStartHour: 4)
    let variant = MeasureVariant(duration: .seconds(60), kind: .plain, language: .ru)
    let other = MeasureVariant(duration: .seconds(120), kind: .plain, language: .ru)
    try recorder.commit { try recorder.recordMeasurement(measureResult(at: date(1, 12)), variant: other, replay: nil) }
    for day in 1...7 {
        try recorder.commit { try recorder.recordMeasurement(measureResult(at: date(day, 12)), variant: variant, replay: nil) }
    }
    let kept = try context.fetch(FetchDescriptor<SpeedMeasurement>(sortBy: [SortDescriptor(\.date)]))
        .filter { $0.duration == "60" }
    let days = kept.map { Calendar.current.component(.day, from: $0.date) }
    #expect(days == [1, 3, 4, 5, 6, 7])
    #expect(try context.fetchCount(FetchDescriptor<SpeedMeasurement>()) == 7)   // другой вариант не тронут
    #expect(try context.fetchCount(FetchDescriptor<SessionRecord>()) == 8)      // сессии не удаляются
}

@Test func measureModeCountsAsPracticeInAnalytics() {
    #expect(Analytics.isQualifyingLength(mode: .measure, kind: nil, chars: 300))
    #expect(!Analytics.isQualifyingLength(mode: .measure, kind: nil, chars: 100))
    #expect(SessionHistory.modeTitle("measure") == "Замер скорости")
}
