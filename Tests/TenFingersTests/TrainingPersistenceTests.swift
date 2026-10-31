import Foundation
import SwiftData
import Testing
import TypingCore
@testable import TenFingers

private func result(at date: Date) -> ExerciseResult {
    var engine = TypingEngine(text: "ао")
    _ = engine.handle(Keystroke(character: "а", keyCode: 3, timestamp: 0))
    _ = engine.handle(Keystroke(character: "x", keyCode: 7, timestamp: 0.2))
    _ = engine.handle(Keystroke(character: "о", keyCode: 38, timestamp: 0.5))
    return ExerciseResult(engine: engine, mode: .course, language: .ru, lessonId: "ru.1.1",
                          startedAt: date, endedAt: date, hintLevel: .full)
}

@MainActor @Test func adaptiveStateIsCreatedThenUpdated() throws {
    let container = try ModelStore.makeContainer(inMemory: true)
    let context = container.mainContext
    let recorder = ResultRecorder(context: context, dayStartHour: 4)
    let reader = StatsReader(context: context)
    #expect(try reader.unlockedCount(language: .ru) == 6)
    try recorder.commit { try recorder.recordAdaptive(language: .ru, unlockedCount: 8) }
    try recorder.commit { try recorder.recordAdaptive(language: .ru, unlockedCount: 9) }
    #expect(try context.fetchCount(FetchDescriptor<AdaptiveState>()) == 1)
    #expect(try reader.unlockedCount(language: .ru) == 9)
    #expect(try reader.unlockedCount(language: .en) == 6)
}

@MainActor @Test func keyMasteryComesFromKeyStats() throws {
    let container = try ModelStore.makeContainer(inMemory: true)
    let context = container.mainContext
    let recorder = ResultRecorder(context: context, dayStartHour: 4)
    try recorder.commit { try recorder.record(result(at: Date(timeIntervalSince1970: 1_000_000))) }
    let mastery = try StatsReader(context: context).keyMastery(language: .ru)
    #expect(mastery["о"] == KeyMastery(ewmaMs: 500, errorRate: 1.0, presses: 1))
    #expect(try StatsReader(context: context).keyMastery(language: .en).isEmpty)
}

@MainActor @Test func keyMasteryErrorRateUsesRecentWindow() throws {
    let container = try ModelStore.makeContainer(inMemory: true)
    let context = container.mainContext
    let stat = KeyStat(language: "ru", character: "а")
    stat.presses = 100
    stat.errors = 50
    stat.ewmaMs = 300
    stat.recent = Array(repeating: false, count: 49) + [true]
    context.insert(stat)
    let mastery = try StatsReader(context: context).keyMastery(language: .ru)
    #expect(mastery["а"] == KeyMastery(ewmaMs: 300, errorRate: 0.02, presses: 100))
}

@MainActor @Test func keyMasteryFoldsCapitalsIntoLowercase() throws {
    let container = try ModelStore.makeContainer(inMemory: true)
    let context = container.mainContext
    let capital = KeyStat(language: "ru", character: "А")
    capital.presses = 20
    capital.errors = 2
    capital.ewmaMs = 400
    capital.recent = Array(repeating: false, count: 20)
    let lower = KeyStat(language: "ru", character: "а")
    lower.presses = 20
    lower.errors = 0
    lower.ewmaMs = 200
    lower.recent = Array(repeating: false, count: 20)
    context.insert(capital)
    context.insert(lower)
    let mastery = try StatsReader(context: context).keyMastery(language: .ru)
    #expect(mastery["А"] == nil)
    #expect(mastery["а"]?.presses == 40)
    #expect(mastery["а"]?.ewmaMs == 300)
    #expect(mastery["а"]?.errorRate == 0)
}

@MainActor @Test func keyMasteryFoldIgnoresMissingEwma() throws {
    let container = try ModelStore.makeContainer(inMemory: true)
    let context = container.mainContext
    let capital = KeyStat(language: "ru", character: "Б")
    capital.presses = 5
    let lower = KeyStat(language: "ru", character: "б")
    lower.presses = 10
    lower.ewmaMs = 250
    context.insert(capital)
    context.insert(lower)
    let mastery = try StatsReader(context: context).keyMastery(language: .ru)
    #expect(mastery["б"] == KeyMastery(ewmaMs: 250, errorRate: 0, presses: 15))
}

@MainActor @Test func bigramMasteryAccumulates() throws {
    let container = try ModelStore.makeContainer(inMemory: true)
    let context = container.mainContext
    let recorder = ResultRecorder(context: context, dayStartHour: 4)
    try recorder.commit { try recorder.record(result(at: Date(timeIntervalSince1970: 1_000_000))) }
    try recorder.commit { try recorder.record(result(at: Date(timeIntervalSince1970: 1_000_100))) }
    let mastery = try StatsReader(context: context).bigramMastery(language: .ru)
    #expect(mastery["ао"]?.presses == 2)
}

@MainActor @Test func customTextAdvances() throws {
    let container = try ModelStore.makeContainer(inMemory: true)
    let context = container.mainContext
    let recorder = ResultRecorder(context: context, dayStartHour: 4)
    let text = CustomText(title: "Заметка", body: "Привет, мир", language: "ru")
    context.insert(text)
    try context.save()
    #expect(text.offset == 0)
    try recorder.commit { recorder.advanceCustomText(text, to: 500) }
    let fetched = try #require(try context.fetch(FetchDescriptor<CustomText>()).first)
    #expect(fetched.offset == 11)  // позиция обрезается до длины текста
    #expect(fetched.title == "Заметка")
}

// MARK: - «Пальцы»

private func sessionRecord(day: String, language: String = "ru", presses: [Finger: Int], errors: [Finger: Int]) -> SessionRecord {
    SessionRecord(mode: "weak", language: language, lessonId: nil, startedAt: .now, endedAt: .now, logicalDay: day,
                  activeSeconds: 30, chars: 100, errorCount: 0, cpm: 200, accuracy: 1, completed: true,
                  hintLevel: "full", maxErrorStreak: 0, wrongKeystrokes: 0,
                  fingerPresses: FingerCounts.data(presses), fingerErrors: FingerCounts.data(errors))
}

@MainActor @Test func fingerTotalsSumTheWindowOfLogicalDays() throws {
    let container = try ModelStore.makeContainer(inMemory: true)
    let context = container.mainContext
    context.insert(sessionRecord(day: "2027-01-14", presses: [.leftPinky: 20, .thumb: 5], errors: [.leftPinky: 1]))
    context.insert(sessionRecord(day: "2027-01-01", presses: [.leftPinky: 30], errors: [.leftPinky: 2]))   // 14-й день назад
    context.insert(sessionRecord(day: "2026-12-31", presses: [.leftPinky: 99], errors: [.leftPinky: 9]))   // вне окна
    context.insert(sessionRecord(day: "2027-01-10", language: "en", presses: [.leftPinky: 77], errors: [:]))
    context.insert(SessionRecord(mode: "weak", language: "ru", lessonId: nil, startedAt: .now, endedAt: .now,
                                 logicalDay: "2027-01-12", activeSeconds: 1, chars: 1, errorCount: 0, cpm: 1,
                                 accuracy: 1, completed: true, hintLevel: "full", maxErrorStreak: 0, wrongKeystrokes: 0))
    let totals = try StatsReader(context: context).fingerTotals(language: .ru, days: 14, today: "2027-01-14")
    #expect(totals.presses == [.leftPinky: 50])   // большой палец не оценивается — не суммируется
    #expect(totals.errors == [.leftPinky: 3])
}

@MainActor @Test func keyEwmaKeepsOnlyKeysWithTime() throws {
    let container = try ModelStore.makeContainer(inMemory: true)
    let context = container.mainContext
    let timed = KeyStat(language: "ru", character: "а")
    timed.presses = 40
    timed.ewmaMs = 250
    let untimed = KeyStat(language: "ru", character: "б")
    untimed.presses = 10
    context.insert(timed)
    context.insert(untimed)
    let ewma = try StatsReader(context: context).keyEwma(language: .ru)
    #expect(ewma.count == 1)
    #expect(ewma["а"]?.ms == 250 && ewma["а"]?.presses == 40)
}

@MainActor @Test func fingerPortionIsRecordedAsWeakWithFingerSource() throws {
    let container = try ModelStore.makeContainer(inMemory: true)
    let context = container.mainContext
    let recorder = ResultRecorder(context: context, dayStartHour: 4)
    let source = FingerTraining.source(.leftPinky, .accuracy)
    #expect(source == "finger:leftPinky:accuracy")
    var engine = TypingEngine(text: "ао")
    _ = engine.handle(Keystroke(character: "а", keyCode: 0, timestamp: 0))
    _ = engine.handle(Keystroke(character: "о", keyCode: 31, timestamp: 0.3))
    let result = ExerciseResult(engine: engine, mode: .weak, language: .ru, lessonId: nil,
                                startedAt: .now, endedAt: .now, hintLevel: .full)
    try recorder.commit { try recorder.record(result, source: source) }
    let record = try #require(try context.fetch(FetchDescriptor<SessionRecord>()).first)
    #expect(record.mode == "weak" && record.source == "finger:leftPinky:accuracy" && record.lessonId == nil)
}

@MainActor @Test func fingerLettersComeFromKeyStatsWithoutActiveLayout() throws {
    let container = try ModelStore.makeContainer(inMemory: true)
    let context = container.mainContext
    for (letter, code, presses) in [("а", 3, 100), ("А", 3, 5), ("о", 38, 80), ("ж", 41, 0), ("п", 0, 7)] {
        let stat = KeyStat(language: "ru", character: letter)
        stat.keyCode = code
        stat.presses = presses
        context.insert(stat)
    }
    let english = KeyStat(language: "en", character: "a")
    english.keyCode = 0
    context.insert(english)
    // Раскладки нет (пустая карта запаса): буквы пальцев берутся из истории клавиш; «п» с кодом по умолчанию 0 — не мизинец.
    let map = try StatsReader(context: context).fingerLetters(language: .ru, layout: [:])
    #expect(map == ["а": .leftIndex, "о": .rightIndex, "ж": .rightPinky])
    // Раскладка — запасом для букв без истории.
    let withLayout = try StatsReader(context: context).fingerLetters(language: .ru, layout: ["п": .rightIndex])
    #expect(withLayout["п"] == .rightIndex && withLayout["а"] == .leftIndex)
}
