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
