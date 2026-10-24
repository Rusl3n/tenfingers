import Foundation
import Testing
@testable import TypingCore

private func finishedEngine() -> TypingEngine {
    var engine = TypingEngine(text: "аа о")
    _ = engine.handle(Keystroke(character: "а", keyCode: 3, timestamp: 0))
    _ = engine.handle(Keystroke(character: "x", keyCode: 7, timestamp: 0.1))
    _ = engine.handle(Keystroke(character: "а", keyCode: 3, timestamp: 0.3))
    _ = engine.handle(Keystroke(character: " ", keyCode: 49, timestamp: 0.5))
    _ = engine.handle(Keystroke(character: "о", keyCode: 38, timestamp: 0.9))
    return engine
}

@Test func resultCopiesEngineState() {
    let start = Date(timeIntervalSince1970: 1_000)
    let result = ExerciseResult(engine: finishedEngine(), mode: .course, language: .ru, lessonId: "ru.1.1",
                                startedAt: start, endedAt: start.addingTimeInterval(1), hintLevel: .full)
    #expect(result.completed)
    #expect(result.chars == 4)
    #expect(result.errorCount == 1)
    #expect(result.accuracy == 0.75)
    #expect(result.activeSeconds == 0.9)
    #expect(result.wrongKeystrokes == 1)
}

@Test func samplesGroupByCharacterAndSkipSpace() {
    let result = ExerciseResult(engine: finishedEngine(), mode: .course, language: .ru, lessonId: nil,
                                startedAt: .now, endedAt: .now, hintLevel: .full)
    let samples = KeyStats.samples(from: result)
    #expect(samples[" "] == nil)
    #expect(samples["а"]?.outcomes == [false, true])
    #expect(samples["а"]?.intervalsMs.count == 1)
    #expect(samples["о"]?.keyCode == 38)
}

@Test func ewmaStartsFromFirstSample() {
    #expect(KeyStats.ewma(nil, 300) == 300)
    #expect(KeyStats.ewma(300, 400) == 310)
}

@Test func recentWindowKeepsLast50() {
    let recent = KeyStats.appendRecent(Array(repeating: false, count: 49), [true, true])
    #expect(recent.count == 50)
    #expect(recent.suffix(2) == [true, true])
}

@Test func logicalDayStartsAtConfiguredHour() {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Europe/Moscow")!
    let night = calendar.date(from: DateComponents(year: 2026, month: 10, day: 24, hour: 2))!
    let morning = calendar.date(from: DateComponents(year: 2026, month: 10, day: 24, hour: 5))!
    #expect(LogicalDay.key(for: night, dayStartHour: 4, calendar: calendar) == "2026-10-23")
    #expect(LogicalDay.key(for: morning, dayStartHour: 4, calendar: calendar) == "2026-10-24")
    #expect(LogicalDay.key(for: night, dayStartHour: 0, calendar: calendar) == "2026-10-24")
}

@Test func pinkyCountsUseFingerMap() {
    // ф (keyCode 0, левый мизинец) без ошибки, а (3, указательный) с ошибкой, ж (41, правый мизинец) с ошибкой
    var engine = TypingEngine(text: "фаж")
    _ = engine.handle(Keystroke(character: "ф", keyCode: 0, timestamp: 0))
    _ = engine.handle(Keystroke(character: "x", keyCode: 7, timestamp: 0.1))
    _ = engine.handle(Keystroke(character: "а", keyCode: 3, timestamp: 0.2))
    _ = engine.handle(Keystroke(character: "x", keyCode: 7, timestamp: 0.3))
    _ = engine.handle(Keystroke(character: "ж", keyCode: 41, timestamp: 0.4))
    let result = ExerciseResult(engine: engine, mode: .course, language: .ru, lessonId: nil,
                                startedAt: .now, endedAt: .now, hintLevel: .full)
    let counts = KeyStats.pinkyCounts(from: result)
    #expect(counts.presses == 2)
    #expect(counts.errors == 1)
}

@Test func exerciseKindIsOptionalAndCarried() {
    let plain = ExerciseResult(engine: finishedEngine(), mode: .course, language: .ru, lessonId: nil,
                               startedAt: .now, endedAt: .now, hintLevel: .full)
    #expect(plain.exerciseKind == nil)
    let check = ExerciseResult(engine: finishedEngine(), mode: .course, language: .ru, lessonId: nil,
                               startedAt: .now, endedAt: .now, hintLevel: .full, exerciseKind: .check)
    #expect(check.exerciseKind == .check)
}

@Test func logicalDayHandlesDaylightSavingTransition() {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Europe/Berlin")!
    // 29 марта 2026 в Берлине часы переводятся с 02:00 на 03:00
    let afterStart = calendar.date(from: DateComponents(year: 2026, month: 3, day: 29, hour: 4, minute: 30))!
    let beforeStart = calendar.date(from: DateComponents(year: 2026, month: 3, day: 29, hour: 3, minute: 30))!
    #expect(LogicalDay.key(for: afterStart, dayStartHour: 4, calendar: calendar) == "2026-03-29")
    #expect(LogicalDay.key(for: beforeStart, dayStartHour: 4, calendar: calendar) == "2026-03-28")
    // осенний перевод: 25 октября 2026, 03:00 → 02:00
    let autumn = calendar.date(from: DateComponents(year: 2026, month: 10, day: 25, hour: 4, minute: 0))!
    #expect(LogicalDay.key(for: autumn, dayStartHour: 4, calendar: calendar) == "2026-10-25")
}

@Test func bigramSamplesUseConsecutiveLettersOnly() {
    var engine = TypingEngine(text: "ав ло")
    let keys: [(Character, Double)] = [("а", 0), ("в", 0.3), (" ", 0.5), ("л", 0.7), ("x", 0.8), ("о", 1.0)]
    for (c, t) in keys { _ = engine.handle(Keystroke(character: c, keyCode: 0, timestamp: t)) }
    let result = ExerciseResult(engine: engine, mode: .adaptive, language: .ru, lessonId: nil,
                                startedAt: .now, endedAt: .now, hintLevel: .full)
    let bigrams = KeyStats.bigramSamples(from: result)
    #expect(Set(bigrams.keys) == ["ав", "ло"])
    #expect(bigrams["ав"]?.outcomes == [false])
    #expect(bigrams["ло"]?.outcomes == [true])
    #expect(bigrams["ав"]?.intervalsMs.count == 1)
}

@Test func bigramsAreLowercased() {
    var engine = TypingEngine(text: "Ав")
    _ = engine.handle(Keystroke(character: "А", keyCode: 3, timestamp: 0))
    _ = engine.handle(Keystroke(character: "в", keyCode: 2, timestamp: 0.2))
    let result = ExerciseResult(engine: engine, mode: .course, language: .ru, lessonId: nil,
                                startedAt: .now, endedAt: .now, hintLevel: .full)
    #expect(KeyStats.bigramSamples(from: result).keys.contains("ав"))
}

@Test func fingerCountsIncludeSpaceAndErrors() {
    // ф (0) без ошибки, а (3) с ошибкой, пробел (49), ё (50) без ошибки, Ё (50) с ошибкой
    var engine = TypingEngine(text: "фа ёЁ")
    let keys: [(Character, UInt16, Double)] = [
        ("ф", 0, 0), ("x", 7, 0.1), ("а", 3, 0.2), (" ", 49, 0.3), ("ё", 50, 0.4), ("x", 7, 0.5), ("Ё", 50, 0.6),
    ]
    for (c, code, t) in keys { _ = engine.handle(Keystroke(character: c, keyCode: code, timestamp: t)) }
    let result = ExerciseResult(engine: engine, mode: .practice, language: .ru, lessonId: nil,
                                startedAt: .now, endedAt: .now, hintLevel: .full)
    let counts = KeyStats.fingerCounts(from: result)
    let a = FingerMap.finger(for: 3)!, f = FingerMap.finger(for: 0)!, yo = FingerMap.finger(for: 50)!
    #expect(FingerMap.finger(for: 49) == .thumb)
    var presses: [Finger: Int] = [:], errors: [Finger: Int] = [:]
    for (finger, press, error) in [(f, 1, 0), (a, 1, 1), (Finger.thumb, 1, 0), (yo, 2, 1)] {
        presses[finger, default: 0] += press
        errors[finger, default: 0] += error
    }
    #expect(counts.presses == presses)
    #expect(counts.errors == errors)
    // Палец с нажатиями есть в обоих словарях, даже без ошибок.
    #expect(counts.errors[.thumb] == 0)
    #expect(Set(counts.presses.keys) == Set(counts.errors.keys))
}

@Test func yoCorrectCountsBothCasesWithoutErrors() {
    var engine = TypingEngine(text: "ёЁёа")
    let keys: [(Character, UInt16, Double)] = [
        ("ё", 50, 0), ("Ё", 50, 0.1), ("x", 7, 0.2), ("ё", 50, 0.3), ("а", 3, 0.4),
    ]
    for (c, code, t) in keys { _ = engine.handle(Keystroke(character: c, keyCode: code, timestamp: t)) }
    let result = ExerciseResult(engine: engine, mode: .practice, language: .ru, lessonId: nil,
                                startedAt: .now, endedAt: .now, hintLevel: .full)
    #expect(KeyStats.yoCorrect(from: result) == 2)
    let english = ExerciseResult(engine: finishedEngine(), mode: .practice, language: .en, lessonId: nil,
                                 startedAt: .now, endedAt: .now, hintLevel: .full)
    #expect(KeyStats.yoCorrect(from: english) == 0)
}

@Test func resultCarriesTextTraitsOfWholeTargetAndStepIndex() {
    var engine = TypingEngine(text: "Да, 2")
    _ = engine.handle(Keystroke(character: "Д", keyCode: 2, timestamp: 0))
    let plain = ExerciseResult(engine: engine, mode: .course, language: .ru, lessonId: nil,
                               startedAt: .now, endedAt: .now, hintLevel: .full)
    #expect(!plain.completed)
    #expect(plain.textTraits == [.capitals, .punctuation, .digits])
    #expect(plain.stepIndex == nil)
    let step = ExerciseResult(engine: engine, mode: .course, language: .ru, lessonId: "ru.1.1",
                              startedAt: .now, endedAt: .now, hintLevel: .full, stepIndex: 2)
    #expect(step.stepIndex == 2)
}
