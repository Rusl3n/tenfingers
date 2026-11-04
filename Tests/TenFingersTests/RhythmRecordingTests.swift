import Foundation
import SwiftData
import Testing
import TypingCore
@testable import TenFingers

private let fingers: [Character: Finger] = ["о": .rightIndex, "л": .rightMiddle, "а": .leftIndex, " ": .thumb]

private func lane(_ character: Character) -> RhythmLane {
    switch character {
    case " ": .space
    case "о": .finger(4)
    case "л": .finger(5)
    default: .finger(3)
    }
}

/// Заход по нотам с шагом в секунду; `presses[i]` — что нажато на i-й ноте (nil — пропуск). Для `cleared == false`
/// в треке остаётся неоценённая нота далеко за сценарием.
private func outcome(_ notes: [Character], presses: [Character?], cleared: Bool = true, mode: RhythmNoteMode = .open,
                     end: Date, seconds: Double = 90, keyCodes: [Character: UInt16] = layoutCodes) -> RhythmOutcome {
    var times = notes.enumerated().map { (1 + Double($0.offset), $0.element) }
    if !cleared { times.append((500, "а")) }
    let chart = RhythmChart(
        notes: times.enumerated().map {
            RhythmNote(index: $0.offset, time: $0.element.0, character: $0.element.1, lane: lane($0.element.1),
                       wordIndex: nil)
        }, duration: 600, level: .preset(.hard))
    var game = RhythmGame(chart: chart)
    for (index, pressed) in presses.enumerated() {
        if let pressed { _ = game.press(pressed, at: 1 + Double(index)) }
    }
    _ = game.tick(at: Double(notes.count) + 2)
    return RhythmOutcome.make(game: game, chart: chart, source: RhythmNoteSource(mode: mode, letters: ["о", "л", "а"]),
                              language: .ru, startedAt: end.addingTimeInterval(-seconds), endedAt: end,
                              activeSeconds: seconds, fingers: fingers, keyCodes: keyCodes)
}

/// Коды клавиш русской раскладки: о — J, л — K, а — F, пробел.
private let layoutCodes: [Character: UInt16] = ["о": 38, "л": 40, "а": 3, " ": 49]

private let evening = Calendar.current.date(from: DateComponents(year: 2026, month: 11, day: 4, hour: 20))!

@MainActor @Test func rhythmEntryIsRecordedAsSessionDayKeyStatsAndResult() throws {
    let container = try ModelStore.makeContainer(inMemory: true)
    let context = container.mainContext
    let existing = KeyStat(language: "ru", character: "о")
    existing.presses = 10
    existing.errors = 2
    existing.ewmaMs = 321
    existing.keyCode = 38
    existing.recent = [true, false]
    context.insert(existing)
    try context.save()

    // о попали, л не та буква, а пропущена, пробел попали.
    let result = outcome(["о", "л", "а", " "], presses: ["о", "x", nil, " "], end: evening)
    let recorder = ResultRecorder(context: context, dayStartHour: { 4 }, goalSeconds: { 600 })
    try recorder.commit { try recorder.recordRhythm(result) }

    let sessions = try context.fetch(FetchDescriptor<SessionRecord>())
    let session = try #require(sessions.first)
    #expect(sessions.count == 1)
    #expect(session.mode == "rhythm" && session.language == "ru" && session.cpm == 0)
    #expect(session.source == "rhythm:open" && session.chars == 4 && session.errorCount == 2)
    #expect(session.completed && session.activeSeconds == 90 && session.lessonId == nil && session.exerciseKind == nil)
    #expect(session.wrongKeystrokes == 1 && session.maxErrorStreak == 2)
    #expect(session.accuracy == 0.5 && session.textTraits == 0)
    #expect(FingerCounts.counts(session.fingerPresses) == [.rightIndex: 1, .rightMiddle: 1, .leftIndex: 1, .thumb: 1])
    #expect(FingerCounts.counts(session.fingerErrors) == [.rightIndex: 0, .rightMiddle: 1, .leftIndex: 1, .thumb: 0])
    #expect(session.logicalDay == "2026-11-04")

    let day = try #require(try context.fetch(FetchDescriptor<DayRecord>()).first)
    #expect(day.activeSeconds == 90 && day.completedExercises == 1 && day.abandonedExercises == 0)
    #expect(day.languages == ["ru"] && day.goalSeconds == 600)

    let stats = Dictionary(uniqueKeysWithValues: try context.fetch(FetchDescriptor<KeyStat>()).map { ($0.character, $0) })
    let o = try #require(stats["о"])
    #expect(o.presses == 11 && o.errors == 2 && o.recent == [true, false, false])
    #expect(o.ewmaMs == 321 && o.keyCode == 38)   // код существующей строки не перезаписан (в раскладке — тот же)
    let l = try #require(stats["л"])
    #expect(l.presses == 1 && l.errors == 1 && l.recent == [true] && l.ewmaMs == nil && l.keyCode == 40)
    #expect(stats["а"]?.errors == 1 && stats["а"]?.keyCode == 3)
    let space = try #require(stats[" "])
    #expect(space.presses == 1 && space.errors == 0 && space.keyCode == 49)
    #expect(try context.fetchCount(FetchDescriptor<BigramStat>()) == 0)

    let stored = try #require(try context.fetch(FetchDescriptor<RhythmResult>()).first)
    #expect(stored.language == "ru" && stored.mode == "open" && stored.level == "hard" && stored.bpm == 80)
    #expect(stored.score == result.score && stored.maxCombo == 1 && stored.cleared)
    #expect(stored.accuracy == 0.5 && stored.grade == "D")
    #expect(stored.startedAt == evening.addingTimeInterval(-90) && stored.endedAt == evening)
    let decoded = try JSONDecoder().decode(RhythmReport.self, from: stored.report)
    #expect(decoded == result.report)
    let judgements = try JSONDecoder().decode([String: Int].self, from: stored.judgements)
    #expect(judgements == result.report.counts)
    #expect(judgements["perfect"] == 2 && judgements["wrongKey"] == 1 && judgements["skipped"] == 1)
}

@MainActor @Test func unfinishedRhythmEntryCountsAsAbandonedAndAddsTime() throws {
    let container = try ModelStore.makeContainer(inMemory: true)
    let context = container.mainContext
    let recorder = ResultRecorder(context: context, dayStartHour: 4)
    try recorder.commit {
        try recorder.recordRhythm(outcome(["о", "л"], presses: ["о", "л"], cleared: false, end: evening, seconds: 30))
        try recorder.recordRhythm(outcome(["о", "л"], presses: ["о", "л"], end: evening.addingTimeInterval(120),
                                          seconds: 60))
    }
    let day = try #require(try context.fetch(FetchDescriptor<DayRecord>()).first)
    #expect(day.activeSeconds == 90 && day.completedExercises == 1 && day.abandonedExercises == 1)
    let sessions = try context.fetch(FetchDescriptor<SessionRecord>(sortBy: [SortDescriptor(\.endedAt)]))
    #expect(sessions.map(\.completed) == [false, true])
    let results = try context.fetch(FetchDescriptor<RhythmResult>(sortBy: [SortDescriptor(\.endedAt)]))
    #expect(results.map(\.cleared) == [false, true] && results.map(\.grade) == ["D", "S"])
}

@MainActor @Test func failedRhythmEntryIsRecordedAsAbandoned() throws {
    let container = try ModelStore.makeContainer(inMemory: true)
    let context = container.mainContext
    let recorder = ResultRecorder(context: context, dayStartHour: 4)
    let notes = [Character](repeating: "о", count: RhythmGame.startHealth / RhythmGame.missPenalty + 1)
    try recorder.commit {
        try recorder.recordRhythm(outcome(notes, presses: [], end: evening))   // 20 пропусков — здоровье кончилось
    }
    let result = try #require(try context.fetch(FetchDescriptor<RhythmResult>()).first)
    #expect(!result.cleared && result.grade == "D")
    #expect(try #require(try context.fetch(FetchDescriptor<DayRecord>()).first).abandonedExercises == 1)
}

@MainActor @Test func existingKeyStatKeepsItsKeyCodeAndNewLettersWithoutCodeAreNotRecorded() throws {
    let container = try ModelStore.makeContainer(inMemory: true)
    let context = container.mainContext
    let existing = KeyStat(language: "ru", character: "о")
    existing.keyCode = 38
    context.insert(existing)
    try context.save()
    // Раскладка называет для «о» другой код (и вообще не знает «л» и пробел): старая строка не меняется,
    // новых строк без кода нет — иначе они попали бы на клавишу с кодом 0.
    let result = outcome(["о", "л", " "], presses: ["о", "л", " "], end: evening, keyCodes: ["о": 99, "а": 3])
    let recorder = ResultRecorder(context: context, dayStartHour: 4)
    try recorder.commit { try recorder.recordRhythm(result) }
    let stats = try context.fetch(FetchDescriptor<KeyStat>())
    #expect(stats.map(\.character) == ["о"])
    #expect(stats.first?.keyCode == 38 && stats.first?.presses == 1)
}

/// Бесконечный заход: двадцать пропусков подряд — здоровье кончилось. Ступень последней оценённой ноты — вторая
/// (нота 16 и дальше — 45 нот в минуту), поэтому бит записи — 45.
private func endlessOutcome(end: Date) -> RhythmOutcome {
    let chart = RhythmChart(
        notes: (0..<40).map { index in
            RhythmNote(index: index, time: 2 + Double(index) * 1.5, character: "о", lane: .finger(4), wordIndex: nil,
                       scrollSeconds: 3.6)
        }, duration: RhythmEndless.trackSeconds, level: .preset(.endless))
    var game = RhythmGame(chart: chart)
    _ = game.tick(at: 1000)
    return RhythmOutcome.make(game: game, chart: chart, source: RhythmNoteSource(mode: .open, letters: ["о"]),
                              language: .ru, startedAt: end.addingTimeInterval(-60), endedAt: end, activeSeconds: 60,
                              fingers: fingers, keyCodes: layoutCodes)
}

@MainActor @Test func endlessEntryEndedByHealthIsACompletedSessionButNotACleared() throws {
    let container = try ModelStore.makeContainer(inMemory: true)
    let context = container.mainContext
    let result = endlessOutcome(end: evening)
    #expect(result.completed && !result.cleared)
    let recorder = ResultRecorder(context: context, dayStartHour: 4)
    try recorder.commit { try recorder.recordRhythm(result) }

    let session = try #require(try context.fetch(FetchDescriptor<SessionRecord>()).first)
    #expect(session.completed && session.mode == "rhythm" && session.source == "rhythm:open")
    let day = try #require(try context.fetch(FetchDescriptor<DayRecord>()).first)
    #expect(day.completedExercises == 1 && day.abandonedExercises == 0 && day.activeSeconds == 60)
    let stored = try #require(try context.fetch(FetchDescriptor<RhythmResult>()).first)
    #expect(stored.level == "endless" && !stored.cleared && stored.grade == "D")
    let report = try JSONDecoder().decode(RhythmReport.self, from: stored.report)
    #expect(report.survivedSeconds != nil && report.peakNotesPerMinute != nil)
    #expect(stored.bpm == RhythmEndless.beatBPM(notesPerMinute: report.peakNotesPerMinute!))
}

@MainActor @Test func endlessEntryQuitEarlyStaysAbandonedAndOrdinaryBpmIsUntouched() throws {
    let container = try ModelStore.makeContainer(inMemory: true)
    let context = container.mainContext
    let chart = RhythmChart(
        notes: [RhythmNote(index: 0, time: 2, character: "о", lane: .finger(4), wordIndex: nil, scrollSeconds: 3.6),
                RhythmNote(index: 1, time: 3.5, character: "о", lane: .finger(4), wordIndex: nil, scrollSeconds: 3.6)],
        duration: RhythmEndless.trackSeconds, level: .preset(.endless))
    var game = RhythmGame(chart: chart)
    _ = game.press("о", at: 2)
    let quit = RhythmOutcome.make(game: game, chart: chart, source: RhythmNoteSource(mode: .open, letters: ["о"]),
                                  language: .ru, startedAt: evening.addingTimeInterval(-20), endedAt: evening,
                                  activeSeconds: 20, fingers: fingers, keyCodes: layoutCodes)
    #expect(!quit.completed && !quit.cleared)
    let recorder = ResultRecorder(context: context, dayStartHour: 4)
    try recorder.commit {
        try recorder.recordRhythm(quit)
        try recorder.recordRhythm(outcome(["о"], presses: ["о"], end: evening.addingTimeInterval(60)))
    }
    let sessions = try context.fetch(FetchDescriptor<SessionRecord>(sortBy: [SortDescriptor(\.endedAt)]))
    #expect(sessions.map(\.completed) == [false, true])
    let results = try context.fetch(FetchDescriptor<RhythmResult>(sortBy: [SortDescriptor(\.endedAt)]))
    #expect(results.map(\.level) == ["endless", "hard"] && results.map(\.cleared) == [false, true])
    #expect(results[0].bpm == 40 && results[1].bpm == 80)   // выход на первой ступени — бит 40; обычный — как был
}
