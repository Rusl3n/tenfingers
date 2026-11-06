import AppKit
import Foundation
import SwiftData
import Testing
import TypingCore
@testable import TenFingers

@MainActor
private func makeSession(_ text: String, limit: Double?, clock: @escaping () -> TimeInterval = { 0 }) -> ExerciseSession {
    let session = ExerciseSession(spec: ExerciseSpec(id: 1, kind: .words, title: "t", text: text),
                                  language: .ru, mode: .measure, lessonId: nil, hint: .full)
    session.layoutLanguage = .ru
    session.configureMeasure(limit: limit)
    session.clock = clock
    return session
}

@MainActor private func press(_ session: ExerciseSession, _ ch: String, at t: TimeInterval) {
    _ = session.handleKey(characters: ch, keyCode: 3, modifiers: [], timestamp: t)
}

// MARK: - Таймер

@Test func timerStartsAtFirstKeyAndExpiresExactly() {
    var timer = MeasureTimer(limit: 60)
    #expect(!timer.isExpired(at: 1000))
    #expect(timer.remaining(at: 1000) == 60)
    timer.start(at: 100)
    #expect(timer.remaining(at: 130) == 30)
    #expect(!timer.isExpired(at: 159.999))
    #expect(timer.isExpired(at: 160))
    #expect(timer.remaining(at: 500) == 0)
}

@Test func timerDoesNotCountPauses() {
    var timer = MeasureTimer(limit: 60)
    timer.pause(at: 5)
    timer.resume(at: 6)
    timer.start(at: 10)
    timer.pause(at: 20)
    #expect(timer.elapsed(at: 50) == 10)
    timer.resume(at: 40)
    #expect(timer.elapsed(at: 50) == 20)
    #expect(timer.isExpired(at: 90))
    #expect(!timer.isExpired(at: 89.9))
}

@MainActor @Test func timedSessionStopsExactlyAtTheLimit() {
    let session = makeSession(String(repeating: "а", count: 50), limit: 60)
    var result: ExerciseResult?
    session.onFinish = { result = $0 }
    press(session, "а", at: 1000)
    press(session, "а", at: 1059.9)
    #expect(result == nil && session.engine.position == 2)
    press(session, "а", at: 1060)
    #expect(session.engine.position == 2)
    #expect(session.engine.isFinished)
    #expect(result?.completed == true && result?.chars == 2)
    press(session, "а", at: 1061)
    #expect(session.engine.position == 2)
}

@MainActor @Test func tickStopsASessionThatNobodyTouches() {
    var now: TimeInterval = 1000
    let session = makeSession(String(repeating: "а", count: 50), limit: 60, clock: { now })
    var finished = 0
    session.onFinish = { _ in finished += 1 }
    press(session, "а", at: 1000)
    now = 1059
    session.expireIfNeeded()
    #expect(finished == 0)
    now = 1060
    session.expireIfNeeded()
    session.expireIfNeeded()
    #expect(finished == 1)
}

@MainActor @Test func pauseFreezesTheMeasureClock() {
    var now: TimeInterval = 1000
    let session = makeSession(String(repeating: "а", count: 50), limit: 60, clock: { now })
    press(session, "а", at: 1000)
    session.pauseForFocusLoss()
    now = 1500
    press(session, "а", at: 1500)   // снимает паузу, знак не засчитывается
    #expect(session.engine.position == 1)
    press(session, "а", at: 1550)
    #expect(session.engine.position == 2)
    #expect(session.measureTimer?.remaining(at: 1550) == 10)
}

@MainActor @Test func text300RunsToTheEndOfTheTextWithoutTimer() {
    let session = makeSession("абв", limit: nil)
    var result: ExerciseResult?
    session.onFinish = { result = $0 }
    #expect(session.measureTimer == nil)
    press(session, "а", at: 0)
    press(session, "б", at: 5000)
    #expect(result == nil)
    press(session, "в", at: 9000)
    #expect(result?.completed == true && result?.chars == 3)
}

@MainActor @Test func backspaceIsIgnoredAndEscapeLeavesWithoutPause() {
    let session = makeSession("аб", limit: nil)
    var escaped = 0
    session.onEscape = { escaped += 1 }
    press(session, "а", at: 0)
    _ = session.handleKey(characters: "\u{7f}", keyCode: 51, modifiers: [], timestamp: 1)
    #expect(session.engine.position == 1 && session.keyLog?.keys.count == 1)
    _ = session.handleKey(characters: "\u{1b}", keyCode: 53, modifiers: [], timestamp: 2)
    #expect(escaped == 1 && !session.isPaused)
}

@MainActor @Test func accuracyCountsOnlyTypedCharsOfALongText() {
    let session = makeSession(String(repeating: "а", count: 1000), limit: 60)
    press(session, "а", at: 0)
    press(session, "ж", at: 0.2)
    press(session, "а", at: 0.4)
    press(session, "а", at: 0.6)
    #expect(session.engine.errorPositions.count == 1)
    #expect(abs(session.engine.accuracy - 2.0 / 3) < 1e-9)
}

// MARK: - Запись нажатий

@MainActor @Test func keyLogKeepsPositionTypedCharAndOffsetFromFirstKey() throws {
    let session = makeSession("аб", limit: nil)
    press(session, "а", at: 500)
    press(session, "ж", at: 500.25)
    press(session, "б", at: 501)
    let keys = try #require(session.keyLog?.keys)
    #expect(keys == [ReplayKey(position: 0, typed: "а", offsetMs: 0),
                     ReplayKey(position: 1, typed: "ж", offsetMs: 250),
                     ReplayKey(position: 1, typed: "б", offsetMs: 1000)])
    let replay = try #require(session.keyLog?.replay(text: "аб"))
    #expect(MeasureReplay(data: replay.encoded()) == replay)
    #expect(MeasureKeyLog().replay(text: "аб") == nil)
}

// MARK: - Сравнение

@Test func firstMeasureHasNoComparison() {
    #expect(MeasureComparison.make(current: 200, earlier: []) == MeasureComparison(toFirst: nil, toPrevious: nil))
}

@Test func comparisonToFirstAndPrevious() {
    #expect(MeasureComparison.make(current: 230, earlier: [200]) == MeasureComparison(toFirst: 30, toPrevious: nil))
    #expect(MeasureComparison.make(current: 230.4, earlier: [200, 250, 240]) == MeasureComparison(toFirst: 30, toPrevious: -10))
}

@Test func comparisonLinesUseTheSpeedUnit() {
    #expect(MeasureResultText.delta(12, unit: .cpm) == "+12 зн/мин")
    #expect(MeasureResultText.delta(-3, unit: .cpm) == "−3 зн/мин")
    #expect(MeasureResultText.delta(10, unit: .wpm) == "+2 WPM")
    #expect(MeasureResultText.lines(MeasureComparison(toFirst: nil, toPrevious: nil), unit: .cpm).count == 1)
    let lines = MeasureResultText.lines(MeasureComparison(toFirst: 30, toPrevious: -10), unit: .cpm)
    #expect(lines.count == 2 && lines[0].contains("+30 зн/мин") && lines[1].contains("−10 зн/мин"))
}

@Test func historyComparisonUsesLastEntryAgainstEarlierOnes() {
    let base = Date(timeIntervalSince1970: 1_000_000)
    let entries = [200, 260, 240].enumerated().map {
        MeasureHistoryEntry(date: base.addingTimeInterval(Double($0.offset) * 100), cpm: Double($0.element))
    }
    #expect(MeasureHistory.comparison(entries.reversed()) == MeasureComparison(toFirst: 40, toPrevious: -20))
}

@Test func historyShowsFirstAndLastFive() {
    let base = Date(timeIntervalSince1970: 1_000_000)
    let entries = (0..<9).map { MeasureHistoryEntry(date: base.addingTimeInterval(Double($0)), cpm: Double($0)) }
    #expect(MeasureHistory.shown(entries.reversed()).map(\.cpm) == [0, 4, 5, 6, 7, 8])
}

// MARK: - Выбор и карточка

@Test func choiceRoundTripsAndFallsBackToDefault() {
    for duration in MeasureDuration.allCases {
        for kind in MeasureTextKind.allCases {
            let choice = MeasureChoice(duration: duration, kind: kind)
            #expect(MeasureChoice(rawValue: choice.rawValue) == choice)
        }
    }
    #expect(MeasureChoice(rawValue: "мусор") == .default)
    #expect(MeasureChoice(rawValue: "77:plain") == .default)
    #expect(SettingsDefault.measureChoice == "60:plain")
    #expect(MeasureChoice.default.variant(language: .en).key == "60:plain:en")
}

@MainActor @Test func choiceTravelsWithArchive() throws {
    let container = try ModelStore.makeContainer(inMemory: true)
    let (source, sourceName) = makeTestDefaults("measureChoice")
    let (target, targetName) = makeTestDefaults("measureChoice")
    defer { removeTestDefaults(sourceName); removeTestDefaults(targetName) }
    source.set("text300:digits", forKey: SettingsKey.measureChoice)
    let archive = try ProgressArchive.decode(ProgressArchive.export(context: container.mainContext,
                                                                    defaults: source, now: .now))
    #expect(archive.settings[SettingsKey.measureChoice] == .string("text300:digits"))
    ProgressArchive.applyPreferences(of: archive, to: target)
    #expect(target.string(forKey: SettingsKey.measureChoice) == "text300:digits")
}

@Test func unavailableKindsAreInactiveWithHintAndChoiceFallsBackToPlain() {
    let keys = MeasureKeys(open: Set("оеаинтсрвлк"), capitalsLearned: false)
    let stored = MeasureChoice(duration: .seconds(120), kind: .digits)
    let model = MeasureCardModel.make(stored: stored, language: .ru, keys: keys, entries: [])
    #expect(model.availability[.plain] == .available)
    #expect(model.availability[.capsPunctuation] == .needsCapitals)
    #expect(model.availability[.digits] == .needsDigits)
    #expect(model.availability[.digits]?.hint != nil && model.availability[.plain]?.hint == nil)
    #expect(model.choice == MeasureChoice(duration: .seconds(120), kind: .plain))
    #expect(model.canStart && model.last == nil)
    let none = MeasureCardModel.make(stored: .default, language: .ru, keys: MeasureKeys(open: [], capitalsLearned: false),
                                     entries: [])
    #expect(!none.canStart && none.availability[.plain] == .needsLetters)
}

@Test func keysFromCourseIncludeLettersDigitsAndCapitals() throws {
    let course = try CourseCatalog.load(.ru)
    let none = MeasureKeys.combine(language: .ru, courses: [course], passedLessonIds: [], adaptiveLetters: ["о", "е"])
    #expect(none.open == ["о", "е"] && !none.capitalsLearned)
    let all = MeasureKeys.combine(language: .ru, courses: [course], passedLessonIds: Set(course.lessons.map(\.id)),
                                  adaptiveLetters: [])
    #expect(all.capitalsLearned)
    #expect(Language.ru.letters.isSubset(of: all.open))
    #expect(all.open.contains(where: \.isNumber) && !all.open.contains(" "))
    #expect(MeasureText.availability(kind: .digits, language: .ru, open: all.open, capitalsLearned: true) == .available)
}

// MARK: - Сохранение

@MainActor @Test func finishedMeasureIsSavedOnceAsSessionAndMeasurementWithReplay() throws {
    let container = try ModelStore.makeContainer(inMemory: true)
    let context = container.mainContext
    let coordinator = ExerciseCoordinator(recorder: ResultRecorder(context: context, dayStartHour: 4), playSound: { _ in })
    let variant = MeasureVariant(duration: .text300, kind: .plain, language: .ru)
    var result: ExerciseResult?
    let session = coordinator.start(spec: ExerciseSpec(id: 1, kind: .words, title: "t", text: "аб"), language: .ru,
                                    mode: .measure, lessonId: nil, hint: .full) { _, r in result = r }
    session.layoutLanguage = .ru
    session.configureMeasure(limit: nil)
    press(session, "а", at: 0)
    press(session, "ж", at: 0.3)
    press(session, "б", at: 0.6)
    let done = try #require(result)
    let replay = session.keyLog?.replay(text: done.text)
    #expect(coordinator.recordFinish(session, done, measurement: (variant, replay, nil)))
    #expect(try context.fetchCount(FetchDescriptor<SessionRecord>()) == 1)
    let saved = try #require(try StatsReader(context: context).measurements(variant: variant).first)
    #expect(saved.hasReplay && saved.chars == 2 && saved.errors == 1)
    #expect(abs(saved.accuracy - 0.5) < 1e-9)
    let session0 = try #require(try context.fetch(FetchDescriptor<SessionRecord>()).first)
    #expect(session0.mode == "measure" && session0.source == "measure:\(variant.key)")
}

@MainActor @Test func leavingBeforeTheEndSavesNothing() throws {
    let container = try ModelStore.makeContainer(inMemory: true)
    let context = container.mainContext
    let coordinator = ExerciseCoordinator(recorder: ResultRecorder(context: context, dayStartHour: 4), playSound: { _ in })
    let session = coordinator.start(spec: ExerciseSpec(id: 1, kind: .words, title: "t", text: "абв"), language: .ru,
                                    mode: .measure, lessonId: nil, hint: .full) { _, _ in }
    session.layoutLanguage = .ru
    session.configureMeasure(limit: 60)
    press(session, "а", at: 0)
    session.stop()
    session.onFinish = nil
    session.markRecorded()
    coordinator.recordAbandonIfNeeded()
    #expect(try context.fetchCount(FetchDescriptor<SessionRecord>()) == 0)
    #expect(try context.fetchCount(FetchDescriptor<SpeedMeasurement>()) == 0)
}

@Test func measureIconsExist() {
    #expect(NSImage(systemSymbolName: "flag", accessibilityDescription: nil) != nil)
}
