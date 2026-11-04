import Foundation
import SwiftData
import Testing
import TypingCore
@testable import TenFingers

private let fingers: [Character: Finger] = [
    "ф": .leftPinky, "ы": .leftRing, "в": .leftMiddle, "а": .leftIndex,
    "о": .rightIndex, "л": .rightMiddle, "д": .rightRing, "ж": .rightPinky,
]
private let eight: Set<Character> = Set(fingers.keys)
private let evening = Calendar.current.date(from: DateComponents(year: 2026, month: 11, day: 4, hour: 20))!

/// Коды клавиш русской раскладки для букв теста.
private let keyCodes: [Character: UInt16] = ["ф": 0, "ы": 1, "в": 2, "а": 3, "о": 38, "л": 40, "д": 37, "ж": 41]

@MainActor
private func makeCoordinator(open: Set<Character> = eight, words: [String] = [], context: ModelContext,
                             recorder: ResultRecorder? = nil,
                             keyCode: @escaping @MainActor (Character) -> UInt16? = { keyCodes[$0] })
    -> RhythmCoordinator {
    let saver = ExerciseCoordinator(recorder: recorder ?? ResultRecorder(context: context, dayStartHour: 4),
                                    playSound: { _ in })
    return RhythmCoordinator(saver: saver, context: context, openLetters: { _ in open }, fingers: { _ in fingers },
                             words: { _ in words }, targetCpm: { 150 }, seed: { 1 }, keyCode: keyCode)
}

private func run(_ mode: RhythmNoteMode = .open, level: RhythmLevelID = .easy) -> RhythmRun {
    RhythmRun(language: .ru, mode: mode, level: level, style: .pulse)
}

/// Короткий трек из трёх нот с шагом в секунду.
private func smallChart(_ letters: [Character] = ["о", "л", "а"]) -> RhythmChart {
    RhythmChart(notes: letters.enumerated().map { index, letter in
        RhythmNote(index: index, time: 1 + Double(index), character: letter,
                   lane: RhythmLane.lane(for: letter, fingers: fingers)!, wordIndex: nil)
    }, duration: 30, level: .preset(.easy))
}

private func startedClock() -> RhythmClock {
    var clock = RhythmClock()
    clock.start(at: 1000)
    return clock
}

@MainActor @Test func prepareClosedWithoutClosedLettersThrows() throws {
    let container = try ModelStore.makeContainer(inMemory: true)
    let coordinator = makeCoordinator(open: Language.ru.letters, context: container.mainContext)
    #expect(throws: RhythmNoteSource.Unavailable.tooFewLetters) { try coordinator.prepare(run: run(.closed)) }
}

@MainActor @Test func prepareOpenBuildsChartWithFingerMap() throws {
    let container = try ModelStore.makeContainer(inMemory: true)
    let coordinator = makeCoordinator(context: container.mainContext)
    let (chart, map) = try coordinator.prepare(run: run(.open, level: .medium))
    #expect(map == fingers)
    #expect(chart.level == .preset(.medium))
    #expect(!chart.notes.isEmpty && chart.notes.allSatisfy { eight.contains($0.character) })
    // Зерно задаёт расстановку: тот же координатор с тем же зерном даёт тот же трек.
    #expect(try coordinator.prepare(run: run(.open, level: .medium)).0 == chart)
}

@MainActor @Test func problemModeNeedsStatsAndWordsModeNeedsWords() throws {
    let container = try ModelStore.makeContainer(inMemory: true)
    let coordinator = makeCoordinator(context: container.mainContext)
    #expect(throws: RhythmNoteSource.Unavailable.noStats) { try coordinator.prepare(run: run(.problem)) }
    #expect(throws: RhythmNoteSource.Unavailable.tooFewWords) { try coordinator.prepare(run: run(.words)) }
    let availability = coordinator.availability(language: .ru)
    #expect(availability[.open] == nil)
    #expect(availability[.problem] == .noStats && availability[.words] == .tooFewWords)
    #expect(availability[.closed] == .tooFewLetters)
}

@MainActor @Test func problemModeUsesErrorRatesOfOpenLetters() throws {
    let container = try ModelStore.makeContainer(inMemory: true)
    let context = container.mainContext
    for (letter, errors) in [("о", 5), ("л", 4), ("а", 3), ("ф", 0)] {
        let stat = KeyStat(language: "ru", character: letter)
        stat.presses = letter == "ф" ? 5 : 20   // меньше 10 нажатий — в слабые не берётся
        stat.errors = errors
        context.insert(stat)
    }
    try context.save()
    let coordinator = makeCoordinator(context: context)
    let (chart, _) = try coordinator.prepare(run: run(.problem))
    #expect(Set(chart.notes.map(\.character)) == ["о", "л", "а"])
}

@MainActor @Test func finishRecordsSessionDayKeyStatsAndResult() throws {
    let container = try ModelStore.makeContainer(inMemory: true)
    let context = container.mainContext
    let coordinator = makeCoordinator(context: context)
    let chart = smallChart()
    var game = RhythmGame(chart: chart)
    for note in chart.notes { _ = game.press(note.character, at: note.time) }
    #expect(game.state == .cleared)

    let result = coordinator.finish(game: game, chart: chart, run: run(), clock: startedClock(), startedAt: evening,
                                    uptime: 1013, now: evening.addingTimeInterval(13))
    let stored = try #require(try context.fetch(FetchDescriptor<RhythmResult>()).first)
    #expect(result.result?.id == stored.id)
    #expect(stored.cleared && stored.mode == "open" && stored.level == "easy" && stored.grade == "S")

    let session = try #require(try context.fetch(FetchDescriptor<SessionRecord>()).first)
    #expect(session.mode == "rhythm" && session.completed && session.chars == 3 && session.cpm == 0)
    #expect(abs(session.activeSeconds - 10) < 0.001)
    let day = try #require(try context.fetch(FetchDescriptor<DayRecord>()).first)
    #expect(day.completedExercises == 1 && abs(day.activeSeconds - 10) < 0.001)
    let stats = try context.fetch(FetchDescriptor<KeyStat>())
    #expect(Set(stats.map(\.character)) == ["о", "л", "а"] && stats.allSatisfy { $0.presses == 1 && $0.ewmaMs == nil })
    // Новые строки букв получили коды клавиш раскладки, а не 0.
    #expect(Dictionary(uniqueKeysWithValues: stats.map { ($0.character, $0.keyCode) }) == ["о": 38, "л": 40, "а": 3])
}

@MainActor @Test func finishWithoutKeyCodesCreatesNoKeyStatRows() throws {
    let container = try ModelStore.makeContainer(inMemory: true)
    let context = container.mainContext
    let coordinator = makeCoordinator(context: context, keyCode: { _ in nil })
    let chart = smallChart()
    var game = RhythmGame(chart: chart)
    for (index, letter) in (["о", "л", "а"] as [Character]).enumerated() { _ = game.press(letter, at: 1 + Double(index)) }
    _ = game.tick(at: 20)
    let result = coordinator.finish(game: game, chart: chart, run: run(), clock: startedClock(), startedAt: evening,
                                    uptime: 1013, now: evening.addingTimeInterval(13))
    #expect(result.result != nil)
    #expect(try context.fetchCount(FetchDescriptor<KeyStat>()) == 0)
    #expect(try context.fetchCount(FetchDescriptor<RhythmResult>()) == 1)
}

/// Сохранение упало: `finish` сообщает о неудаче (экран ждёт алерт), «Повторить» записывает заход и зовёт продолжение.
@MainActor @Test func finishSaveFailureReportsFailedAndRetrySucceeds() throws {
    struct Boom: Error {}
    final class Attempts { var count = 0 }
    let attempts = Attempts()
    let container = try ModelStore.makeContainer(inMemory: true)
    let context = container.mainContext
    var recorder = ResultRecorder(context: context, dayStartHour: 4)
    recorder.beforeSave = {
        attempts.count += 1
        if attempts.count == 1 { throw Boom() }
    }
    let coordinator = makeCoordinator(context: context, recorder: recorder)
    var continued = 0
    coordinator.saver.onRetrySucceeded = { continued += 1 }
    let chart = smallChart()
    var game = RhythmGame(chart: chart)
    for (index, letter) in (["о", "л", "а"] as [Character]).enumerated() { _ = game.press(letter, at: 1 + Double(index)) }
    _ = game.tick(at: 20)
    let outcome = coordinator.finish(game: game, chart: chart, run: run(), clock: startedClock(), startedAt: evening,
                                     uptime: 1013, now: evening.addingTimeInterval(13))
    guard case .failed = outcome else { Issue.record("ожидалась неудача сохранения"); return }
    #expect(coordinator.saver.saveError != nil && continued == 0)
    #expect(try context.fetchCount(FetchDescriptor<RhythmResult>()) == 0)
    coordinator.saver.retrySave()
    #expect(continued == 1)
    #expect(try context.fetchCount(FetchDescriptor<RhythmResult>()) == 1)
}

@MainActor @Test func finishOfFailedGameIsRecordedAsNotCleared() throws {
    let container = try ModelStore.makeContainer(inMemory: true)
    let context = container.mainContext
    let coordinator = makeCoordinator(context: context)
    let chart = smallChart([Character](repeating: "о", count: RhythmGame.startHealth / RhythmGame.missPenalty + 1))
    var game = RhythmGame(chart: chart)
    _ = game.tick(at: 100)   // 20 пропусков — здоровье кончилось
    #expect(game.state == .failed)
    let result = coordinator.finish(game: game, chart: chart, run: run(), clock: startedClock(), startedAt: evening,
                                    uptime: 1010, now: evening)
    #expect(result.result?.cleared == false && result.result?.grade == "D")
    #expect(try #require(try context.fetch(FetchDescriptor<DayRecord>()).first).abandonedExercises == 1)
}

@MainActor @Test func abandonBeforeFirstJudgedNoteWritesNothing() throws {
    let container = try ModelStore.makeContainer(inMemory: true)
    let context = container.mainContext
    let coordinator = makeCoordinator(context: context)
    let chart = smallChart()
    let game = RhythmGame(chart: chart)
    coordinator.abandon(game: game, chart: chart, run: run(), clock: startedClock(), startedAt: evening,
                        uptime: 1020, now: evening)
    #expect(try context.fetchCount(FetchDescriptor<SessionRecord>()) == 0)
    #expect(try context.fetchCount(FetchDescriptor<DayRecord>()) == 0)
    #expect(try context.fetchCount(FetchDescriptor<RhythmResult>()) == 0)
    #expect(try context.fetchCount(FetchDescriptor<KeyStat>()) == 0)
}

@MainActor @Test func wrongLayoutAttemptCountsLikeInExercisesEvenWithoutJudgedNotes() throws {
    let container = try ModelStore.makeContainer(inMemory: true)
    let context = container.mainContext
    let coordinator = makeCoordinator(context: context)
    let chart = smallChart()
    coordinator.abandon(game: RhythmGame(chart: chart), chart: chart, run: run(), clock: startedClock(),
                        startedAt: evening, wrongLayoutAttempted: true, uptime: 1020, now: evening)
    let counter = try #require(try context.fetch(FetchDescriptor<CounterRecord>()).first)
    #expect(counter.name == CounterName.wrongLayoutStarts && counter.value == 1)
    #expect(try context.fetchCount(FetchDescriptor<SessionRecord>()) == 0)
    #expect(try context.fetchCount(FetchDescriptor<RhythmResult>()) == 0)

    var game = RhythmGame(chart: chart)
    for note in chart.notes { _ = game.press(note.character, at: note.time) }
    _ = coordinator.finish(game: game, chart: chart, run: run(), clock: startedClock(), startedAt: evening,
                           wrongLayoutAttempted: true, uptime: 1010, now: evening)
    #expect(try #require(try context.fetch(FetchDescriptor<CounterRecord>()).first).value == 2)
    #expect(try context.fetchCount(FetchDescriptor<RhythmResult>()) == 1)
}

@MainActor @Test func abandonAfterJudgedNoteWritesIncompleteSession() throws {
    let container = try ModelStore.makeContainer(inMemory: true)
    let context = container.mainContext
    let coordinator = makeCoordinator(context: context)
    let chart = smallChart()
    var game = RhythmGame(chart: chart)
    _ = game.press("о", at: 1)
    #expect(coordinator.abandon(game: game, chart: chart, run: run(), clock: startedClock(), startedAt: evening,
                                uptime: 1008, now: evening.addingTimeInterval(8)))
    let session = try #require(try context.fetch(FetchDescriptor<SessionRecord>()).first)
    #expect(!session.completed && session.chars == 1 && session.mode == "rhythm")
    let day = try #require(try context.fetch(FetchDescriptor<DayRecord>()).first)
    #expect(day.abandonedExercises == 1 && day.completedExercises == 0)
    #expect(try #require(try context.fetch(FetchDescriptor<RhythmResult>()).first).cleared == false)
}

@MainActor @Test func recordsCountOnlyClearedEntries() throws {
    let container = try ModelStore.makeContainer(inMemory: true)
    let context = container.mainContext
    let coordinator = makeCoordinator(context: context)
    #expect(coordinator.records(language: .ru, mode: .open, level: .easy) == .empty)

    let chart = smallChart()
    var good = RhythmGame(chart: chart)
    for note in chart.notes { _ = good.press(note.character, at: note.time) }
    var partial = RhythmGame(chart: chart)
    _ = partial.press("о", at: 1)
    _ = coordinator.finish(game: good, chart: chart, run: run(), clock: startedClock(), startedAt: evening,
                           uptime: 1010, now: evening)
    _ = coordinator.abandon(game: partial, chart: chart, run: run(), clock: startedClock(), startedAt: evening,
                            uptime: 1010, now: evening.addingTimeInterval(60))
    let records = coordinator.records(language: .ru, mode: .open, level: .easy)
    #expect(records.bestScore == good.score && records.bestCombo == 3 && records.bestGrade == .s)
    #expect(records.bestAccuracy == 1)
    #expect(coordinator.records(language: .ru, mode: .words, level: .easy) == .empty)
    #expect(coordinator.records(language: .en, mode: .open, level: .easy) == .empty)
}

@MainActor private func insertSession(_ context: ModelContext, mode: String = "adaptive", language: String = "ru",
                                      cpm: Double, chars: Int = 200, completed: Bool = true, minute: Int) {
    let end = evening.addingTimeInterval(Double(minute) * 60)
    context.insert(SessionRecord(mode: mode, language: language, lessonId: nil, startedAt: end.addingTimeInterval(-60),
                                 endedAt: end, logicalDay: "2026-11-04", activeSeconds: 60, chars: chars,
                                 errorCount: 0, cpm: cpm, accuracy: 1, completed: completed, hintLevel: "full",
                                 maxErrorStreak: 0, wrongKeystrokes: 0))
}

@MainActor @Test func personalSpeedIsMedianOfLastTenQualifyingSessions() throws {
    let container = try ModelStore.makeContainer(inMemory: true)
    let context = container.mainContext
    let coordinator = makeCoordinator(context: context)
    #expect(coordinator.personalCpm(language: .ru) == nil)

    // Старая сессия вне последних 10, затем десять подходящих (скорости 100…190) и все неподходящие.
    insertSession(context, cpm: 900, minute: 0)
    for index in 0..<10 { insertSession(context, cpm: 100 + Double(index) * 10, minute: 10 + index) }
    insertSession(context, mode: "rhythm", cpm: 0, chars: 90, minute: 40)
    insertSession(context, mode: "rhythm", cpm: 777, chars: 500, minute: 41)
    insertSession(context, cpm: 800, chars: 99, minute: 42)
    insertSession(context, cpm: 800, completed: false, minute: 43)
    insertSession(context, language: "en", cpm: 800, minute: 44)
    try context.save()

    // Медиана 100,110,…,190 — среднее двух средних: (140 + 150) / 2.
    #expect(coordinator.personalCpm(language: .ru) == 145)
    #expect(coordinator.level(for: .personal, language: .ru) == RhythmLevel.personal(cpm: 145))
    #expect(coordinator.level(for: .hard, language: .ru) == .preset(.hard))
}

@Test func medianHandlesOddEvenAndEmpty() {
    #expect(RhythmCoordinator.median([]) == nil)
    #expect(RhythmCoordinator.median([5]) == 5)
    #expect(RhythmCoordinator.median([9, 1, 5]) == 5)
    #expect(RhythmCoordinator.median([4, 2, 8, 6]) == 5)
}

@Test func everyUnavailableReasonHasShortText() {
    for mode in RhythmNoteMode.allCases {
        for reason in [RhythmNoteSource.Unavailable.tooFewLetters, .tooFewWords, .noStats] {
            #expect(!RhythmCoordinator.reason(reason, mode: mode).isEmpty)
        }
    }
    #expect(RhythmCoordinator.reason(.tooFewLetters, mode: .closed)
            != RhythmCoordinator.reason(.tooFewLetters, mode: .open))
}

@Test func rhythmRunsAreIdentifiedPerLaunch() {
    #expect(run() != run())
    let one = run()
    #expect(one == one)
}

@MainActor @Test func endlessLevelIsThePresetAndTheCoordinatorBuildsTheTwentyMinuteTrack() throws {
    let container = try ModelStore.makeContainer(inMemory: true)
    let coordinator = makeCoordinator(context: container.mainContext)
    #expect(coordinator.level(for: .endless, language: .ru) == .preset(.endless))
    let (chart, map) = try coordinator.prepare(run: run(.open, level: .endless))
    #expect(map == fingers && chart.level == .preset(.endless) && chart.duration == RhythmEndless.trackSeconds)
    #expect(!chart.notes.isEmpty && chart.notes.allSatisfy { eight.contains($0.character) })
    #expect(chart.notes.allSatisfy { $0.scrollSeconds != nil })
    #expect(chart.notes.first?.scrollSeconds == 3.6 && chart.notes.last?.scrollSeconds == 1.6)
    #expect((chart.notes.last?.time ?? 0) > 1100 && (chart.notes.last?.time ?? 0) < RhythmEndless.trackSeconds)
}

@MainActor @Test func endlessRunIsRecordedByHealthAndFeedsOnlyEndlessRecords() throws {
    let container = try ModelStore.makeContainer(inMemory: true)
    let context = container.mainContext
    let coordinator = makeCoordinator(context: context)
    #expect(coordinator.endlessRecords(language: .ru, mode: .open) == .empty)

    let (chart, _) = try coordinator.prepare(run: run(.open, level: .endless))
    var game = RhythmGame(chart: chart)
    for note in chart.notes.prefix(10) { _ = game.press(note.character, at: note.time) }
    _ = game.tick(at: 1000)   // дальше — пропуски до конца здоровья
    #expect(game.state == .failed)
    let outcome = coordinator.finish(game: game, chart: chart, run: run(.open, level: .endless),
                                     clock: startedClock(), startedAt: evening, uptime: 1010, now: evening)
    let stored = try #require(outcome.result)
    #expect(stored.level == "endless" && !stored.cleared)
    let session = try #require(try context.fetch(FetchDescriptor<SessionRecord>()).first)
    #expect(session.completed)

    let records = coordinator.endlessRecords(language: .ru, mode: .open)
    let survived = try #require(try JSONDecoder().decode(RhythmReport.self, from: stored.report).survivedSeconds)
    #expect(records.bestSeconds == survived && records.bestScore == game.score)
    #expect(coordinator.endlessRecords(language: .ru, mode: .words) == .empty)
    #expect(coordinator.records(language: .ru, mode: .open, level: .endless) == .empty)
    #expect(!coordinator.latestSetBest(language: .ru, mode: .open, level: .endless))
}
