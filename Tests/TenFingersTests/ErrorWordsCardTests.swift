import AppKit
import Foundation
import SwiftData
import Testing
import TypingCore
@testable import TenFingers

private let now = Date(timeIntervalSince1970: 1_800_000_000)

private func entries(_ words: [String]) -> [ErrorWordEntry] {
    words.map { ErrorWordEntry(text: $0, isPhrase: false, errors: 2, cleanStreak: 0, firstSeen: now, lastSeen: now) }
}

@Test func cardWithThreeWordsIsUnavailable() {
    let model = ErrorWordsCardModel.make(entries: entries(["окно", "мост", "лес"]), fixed: 4, allowed: nil)
    #expect(model.listCount == 3 && model.eligibleCount == 3 && model.fixed == 4)
    #expect(!model.canStart)
    #expect(model.shortage == "Пока мало слов: 3")
}

@Test func cardWithTwelveWordsIsAvailable() {
    let words = ["окно", "мост", "лес", "дом", "кот", "сад", "рот", "нос", "вес", "сон", "лом", "том"]
    let model = ErrorWordsCardModel.make(entries: entries(words), fixed: 0, allowed: nil)
    #expect(model.canStart && model.shortage == nil && model.eligibleCount == 12)
}

@Test func cardCountsOnlyAllowedLetters() {
    let words = ["окно", "мост", "лес", "дом", "кот", "щётка", "жизнь"]
    let open = Set("октнмсдлеи")
    let model = ErrorWordsCardModel.make(entries: entries(words), fixed: 1, allowed: open)
    #expect(model.listCount == 7 && model.eligibleCount == 5 && model.canStart)
    let fewer = ErrorWordsCardModel.make(entries: entries(words), fixed: 1, allowed: Set("октнм"))
    #expect(!fewer.canStart && fewer.shortage == "Пока мало слов: \(fewer.eligibleCount)")
}

@Test func trainingLettersAllUsesWholeAlphabetOpenUsesOpened() {
    let open = Set(Language.ru.adaptiveOrder.prefix(8))
    #expect(TrainingLetters.all.letters(open: open, language: .ru) == Language.ru.letters)
    #expect(TrainingLetters.open.letters(open: open, language: .ru) == open)
    // Открыт весь алфавит (курс пройден): настройка ни на что не влияет.
    #expect(TrainingLetters.open.letters(open: Language.ru.letters, language: .ru)
            == TrainingLetters.all.letters(open: Language.ru.letters, language: .ru))
    #expect(TrainingLetters(rawValue: "all") == .all && TrainingLetters(rawValue: "open") == .open)
    #expect(SettingsDefault.trainingLetters == TrainingLetters.open.rawValue)
}

@Test func weakSpotsTakeWholeAlphabetWhenSettingIsAll() {
    let weak = KeyMastery(ewmaMs: 900, errorRate: 0.3, presses: 50)
    let stats: [Character: KeyMastery] = ["о": weak, "щ": weak]
    let open = Set(Language.ru.adaptiveOrder.prefix(8))
    let narrow = TrainingLetters.open.letters(open: open, language: .ru)
    let wide = TrainingLetters.all.letters(open: open, language: .ru)
    #expect(!WeakSpotsFocus.keys(stats, letters: narrow, thresholdMs: 343).contains("щ"))
    #expect(WeakSpotsFocus.keys(stats, letters: wide, thresholdMs: 343).contains("щ"))
    let snapshot = TrainingSnapshot.make(language: .ru, unlockedCount: 8, keyMastery: stats, bigramMastery: [:],
                                         targetCpm: 175, openLetters: wide)
    #expect(snapshot.weakKeys.contains("щ"))
}

@Test func errorWordsTextHonoursLetterSetting() {
    let words = ["окно", "мост", "лес", "дом", "кот", "щётка", "жизнь"]
    let open = Set("октнмсдлеи")
    let narrow = ErrorWordsText.make(entries: entries(words), allowed: open, targetChars: 200, seed: 1)
    let text = narrow ?? ""
    #expect(narrow != nil && !text.contains("щ") && !text.contains("ж"))
    let wide = ErrorWordsText.make(entries: entries(words), allowed: Language.ru.letters, targetChars: 200, seed: 1)
    #expect(wide?.contains("щ") == true || wide?.contains("ж") == true)
}

@Test func errorWordsRunKindHasFreshIdAndTitles() {
    let a = RunKind.errorWords(TrainingRun(language: .ru))
    #expect(a.id != RunKind.errorWords(TrainingRun(language: .ru)).id)
    #expect(a.language == .ru && a.planSlot == nil)
    #expect(a.sidebarTitle == "Слова с ошибками идут")
    #expect(ExerciseMode.errorWords.rawValue == "errorWords")
    #expect(SessionHistory.modeTitle("errorWords") == "Слова с ошибками")
}

@MainActor @Test func errorWordsSessionIsRecordedAndCountsLikeTraining() throws {
    let container = try ModelStore.makeContainer(inMemory: true)
    let context = container.mainContext
    var engine = TypingEngine(text: "ао")
    _ = engine.handle(Keystroke(character: "а", keyCode: 3, timestamp: 0))
    _ = engine.handle(Keystroke(character: "о", keyCode: 38, timestamp: 0.4))
    let result = ExerciseResult(engine: engine, mode: .errorWords, language: .ru, lessonId: nil,
                                startedAt: now, endedAt: now, hintLevel: .full)
    let recorder = ResultRecorder(context: context, dayStartHour: 4)
    try recorder.commit { try recorder.record(result, source: "errorWords") }
    let session = try #require(try context.fetch(FetchDescriptor<SessionRecord>()).first)
    #expect(session.mode == "errorWords")
    let day = try #require(try context.fetch(FetchDescriptor<DayRecord>()).first)
    #expect(day.completedExercises == 1 && day.activeSeconds > 0)
    let summary = try ProgressSnapshot(context: context).sessionSummaries(fromDay: "0000-00-00")
    #expect(Analytics.daily(summary, language: .ru).first?.typedSessions == 1)
}

@MainActor @Test func trainingLettersTravelsWithArchive() throws {
    let container = try ModelStore.makeContainer(inMemory: true)
    let (source, sourceName) = makeTestDefaults("trainingLetters")
    let (target, targetName) = makeTestDefaults("trainingLetters")
    defer { removeTestDefaults(sourceName); removeTestDefaults(targetName) }
    source.set("all", forKey: SettingsKey.trainingLetters)
    let archive = try ProgressArchive.decode(ProgressArchive.export(context: container.mainContext,
                                                                    defaults: source, now: now))
    #expect(archive.settings[SettingsKey.trainingLetters] == .string("all"))
    ProgressArchive.applyPreferences(of: archive, to: target)
    #expect(target.string(forKey: SettingsKey.trainingLetters) == "all")
}

@Test func errorWordsIconsExist() {
    #expect(NSImage(systemSymbolName: "text.badge.xmark", accessibilityDescription: nil) != nil)
}
