import Foundation
import SwiftData
import Testing
import TypingCore
@testable import TenFingers

@Test func runKindHasFreshIdForEveryLaunch() {
    let a = RunKind.adaptive(TrainingRun(language: .ru))
    let b = RunKind.adaptive(TrainingRun(language: .ru))
    #expect(a.id != b.id)
    #expect(RunKind.weakSpots(TrainingRun(language: .en)).id != RunKind.weakSpots(TrainingRun(language: .en)).id)
    #expect(RunKind.lesson(LessonRun(language: .ru, lessonId: "ru.1.1")).id
            != RunKind.lesson(LessonRun(language: .ru, lessonId: "ru.1.1")).id)
    #expect(RunKind.practice(PracticeRun(language: .ru, source: .frequentWords)).id != RunKind.practice(PracticeRun(language: .ru, source: .frequentWords)).id)
}

@Test func sidebarOrderPutsTrainingAndPracticeAfterCourse() {
    #expect(SidebarItem.allCases == [.home, .course, .training, .practice, .analytics, .achievements, .settings])
    #expect(SidebarItem.training.icon == "target")
    #expect(SidebarItem.practice.icon == "text.book.closed")
}

@Test func trainingSnapshotShowsLettersFocusAndNext() {
    let slow = KeyMastery(ewmaMs: 600, errorRate: 0, presses: 40)
    let fast = KeyMastery(ewmaMs: 200, errorRate: 0, presses: 40)
    var stats: [Character: KeyMastery] = [:]
    for letter in Language.ru.adaptiveOrder.prefix(6) { stats[letter] = fast }
    stats["е"] = slow
    let snapshot = TrainingSnapshot.make(language: .ru, unlockedCount: 6, keyMastery: stats,
                                         bigramMastery: [:], targetCpm: 175, openLetters: Language.ru.letters)
    #expect(snapshot.letters.map(\.character) == Array("оеаинт"))
    #expect(snapshot.letters.filter(\.isFocus).map(\.character) == ["е"])
    #expect(snapshot.letters.first { $0.character == "о" }?.progress == 1)
    #expect(snapshot.nextLetter == "с")
    #expect(snapshot.weakKeys.first == "е")
    #expect(snapshot.weakBigrams.isEmpty)
    #expect(snapshot.hasWeakSpots)
}

@Test func trainingSnapshotWithoutDataHasNoWeakSpots() {
    let snapshot = TrainingSnapshot.make(language: .en, unlockedCount: 6, keyMastery: [:],
                                         bigramMastery: [:], targetCpm: 175, openLetters: Language.en.letters)
    #expect(!snapshot.hasWeakSpots)
    #expect(snapshot.letters.count == 6)
    let all = TrainingSnapshot.make(language: .en, unlockedCount: 26, keyMastery: [:],
                                    bigramMastery: [:], targetCpm: 175, openLetters: Language.en.letters)
    #expect(all.nextLetter == nil)
}

@Test func weakSpotsFocusKeepsOnlyLanguageLetters() {
    let weak = KeyMastery(ewmaMs: 900, errorRate: 0.2, presses: 50)
    let keys = WeakSpotsFocus.keys([" ": weak, ",": weak, "a": weak, "а": weak], letters: Language.ru.letters, thresholdMs: 343)
    #expect(keys == ["а"])
    let bigrams = WeakSpotsFocus.bigrams(["ab": weak, "ат": weak], letters: Language.ru.letters, thresholdMs: 343)
    #expect(bigrams == ["ат"])
}

@Test func weakSpotsSessionTotalsAccumulateUntilFiveMinutes() {
    var totals = WeakSpotsSessionTotals()
    #expect(!totals.isComplete)
    #expect(totals.accuracy == 1)
    totals.add(seconds: 120, chars: 250, errors: 5)
    totals.add(seconds: 170, chars: 250, errors: 5)
    #expect(!totals.isComplete)
    totals.add(seconds: 10, chars: 20, errors: 0)
    #expect(totals.isComplete)
    #expect(totals.seconds == 300)
    #expect(abs(totals.cpm - 103.4) < 1e-9)   // первый знак каждой из трёх порций времени не имеет
    #expect(abs(totals.accuracy - (1 - 10.0 / 520)) < 1e-9)
}

@MainActor @Test func statsReaderSeesPendingChangesInsideCommit() throws {
    let container = try ModelStore.makeContainer(inMemory: true)
    let context = container.mainContext
    let recorder = ResultRecorder(context: context, dayStartHour: 4)
    var engine = TypingEngine(text: "ао")
    _ = engine.handle(Keystroke(character: "а", keyCode: 0, timestamp: 0))
    _ = engine.handle(Keystroke(character: "о", keyCode: 31, timestamp: 0.3))
    let result = ExerciseResult(engine: engine, mode: .adaptive, language: .ru, lessonId: nil,
                                startedAt: .now, endedAt: .now, hintLevel: .full)
    var seen: [Character: KeyMastery] = [:]
    try recorder.commit {
        try recorder.record(result)
        seen = try StatsReader(context: context).keyMastery(language: .ru)
    }
    #expect(seen["а"]?.presses == 1)
    #expect(seen["о"]?.presses == 1)
}

@MainActor private func seedMastered(_ context: ModelContext, letters: [Character], language: Language = .ru,
                                     ewmaMs: Double = 200) {
    for letter in letters {
        let stat = KeyStat(language: language.rawValue, character: String(letter))
        stat.presses = 40
        stat.ewmaMs = ewmaMs
        context.insert(stat)
    }
}

@MainActor @Test func adaptiveProgressUnlocksNextLetterWhenAllMastered() throws {
    let container = try ModelStore.makeContainer(inMemory: true)
    let context = container.mainContext
    let recorder = ResultRecorder(context: context, dayStartHour: 4)
    let trainer = AdaptiveTrainer(language: .ru, targetCpm: 175)
    seedMastered(context, letters: trainer.unlockedLetters(count: 6))
    var outcome = (before: 0, after: 0)
    try recorder.commit { outcome = try AdaptiveProgress.record(recorder: recorder, trainer: trainer, language: .ru) }
    #expect(outcome.before == 6)
    #expect(outcome.after == 7)
    #expect(try StatsReader(context: context).unlockedCount(language: .ru) == 7)
}

@MainActor @Test func adaptiveProgressStaysWhenNotMastered() throws {
    let container = try ModelStore.makeContainer(inMemory: true)
    let context = container.mainContext
    let recorder = ResultRecorder(context: context, dayStartHour: 4)
    let trainer = AdaptiveTrainer(language: .ru, targetCpm: 175)
    seedMastered(context, letters: Array(trainer.unlockedLetters(count: 6).prefix(5)))
    seedMastered(context, letters: [trainer.unlockedLetters(count: 6)[5]], ewmaMs: 900)
    try recorder.commit { try AdaptiveProgress.record(recorder: recorder, trainer: trainer, language: .ru) }
    #expect(try StatsReader(context: context).unlockedCount(language: .ru) == 6)
}

@MainActor @Test func adaptiveProgressNeverDecreasesStoredCount() throws {
    let container = try ModelStore.makeContainer(inMemory: true)
    let context = container.mainContext
    let recorder = ResultRecorder(context: context, dayStartHour: 4)
    try recorder.commit { try recorder.recordAdaptive(language: .ru, unlockedCount: 9) }
    // Ни одна буква не освоена, но сохранённые 9 букв остаются.
    let trainer = AdaptiveTrainer(language: .ru, targetCpm: 175)
    try recorder.commit { try AdaptiveProgress.record(recorder: recorder, trainer: trainer, language: .ru) }
    #expect(try StatsReader(context: context).unlockedCount(language: .ru) == 9)
}

@MainActor @Test func adaptiveProgressIsPerLanguage() throws {
    let container = try ModelStore.makeContainer(inMemory: true)
    let context = container.mainContext
    let recorder = ResultRecorder(context: context, dayStartHour: 4)
    let trainer = AdaptiveTrainer(language: .en, targetCpm: 175)
    seedMastered(context, letters: trainer.unlockedLetters(count: 6), language: .en)
    try recorder.commit { try AdaptiveProgress.record(recorder: recorder, trainer: trainer, language: .en) }
    #expect(try StatsReader(context: context).unlockedCount(language: .en) == 7)
    #expect(try StatsReader(context: context).unlockedCount(language: .ru) == 6)
}

@MainActor @Test func adaptiveProgressRecordsEachNewlyOpenedLetter() throws {
    let container = try ModelStore.makeContainer(inMemory: true)
    let context = container.mainContext
    let recorder = ResultRecorder(context: context, dayStartHour: 4)
    let trainer = AdaptiveTrainer(language: .ru, targetCpm: 175)
    let date = Date(timeIntervalSince1970: 1_800_000_000)
    seedMastered(context, letters: trainer.unlockedLetters(count: 6))
    try recorder.commit { try AdaptiveProgress.record(recorder: recorder, trainer: trainer, language: .ru, at: date) }
    let unlocks = try context.fetch(FetchDescriptor<AdaptiveUnlock>())
    #expect(unlocks.count == 1)
    #expect(unlocks.first?.letter == String(Language.ru.adaptiveOrder[6]))
    #expect(unlocks.first?.language == "ru")
    #expect(unlocks.first?.unlockedAt == date)
    // Буква уже открыта, новая не освоена: новых записей нет.
    try recorder.commit { try AdaptiveProgress.record(recorder: recorder, trainer: trainer, language: .ru, at: date) }
    #expect(try context.fetchCount(FetchDescriptor<AdaptiveUnlock>()) == 1)
}

// MARK: - «Пальцы»

private func fingerReports() -> [FingerReport] {
    // Левый мизинец — слабый (90%), правый указательный — сильный (100% на 200 нажатиях, быстрые клавиши),
    // левый безымянный — норма (98%), остальные — мало данных.
    FingerTraining.reports(
        presses: [.leftPinky: 100, .rightIndex: 200, .leftRing: 100, .leftMiddle: 10],
        errors: [.leftPinky: 10, .leftRing: 2],
        keyEwma: ["о": (ms: 200, presses: 200)], fingerOf: ["о": .rightIndex], thresholdMs: 343)
}

private let allFingerLetters: [Character: Finger] = ["й": .leftPinky, "о": .rightIndex, "в": .leftMiddle, "ы": .leftRing]

@Test func fingerCardColorsAndButtonsFollowFingerClass() {
    let model = FingerCardModel.make(reports: fingerReports(), fingerOf: allFingerLetters)
    #expect(model.cells.map(\.finger) == [.leftPinky, .leftRing, .leftMiddle, .leftIndex,
                                          .rightIndex, .rightMiddle, .rightRing, .rightPinky])
    func cell(_ finger: Finger) -> FingerCardModel.Cell { model.cells.first { $0.finger == finger }! }
    #expect(cell(.leftPinky).tone == .weak && cell(.leftPinky).drill == .accuracy)
    #expect(cell(.rightIndex).tone == .strong && cell(.rightIndex).drill == .speed)
    #expect(cell(.leftRing).tone == .normal && cell(.leftRing).drill == nil)
    #expect(cell(.leftMiddle).tone == .noData && cell(.leftMiddle).drill == nil)
    #expect(model.hasData)
}

@Test func fingerCardWithoutDataHasNoButtons() {
    let empty = FingerTraining.reports(presses: [.leftPinky: 49], errors: [:], keyEwma: [:], fingerOf: [:],
                                       thresholdMs: 343)
    let model = FingerCardModel.make(reports: empty, fingerOf: allFingerLetters)
    #expect(!model.hasData)
    #expect(model.cells.allSatisfy { $0.tone == .noData && $0.drill == nil })
}

@Test func fingerCardWithoutLettersHasNoButtons() {
    // Слабый и сильный пальцы есть, но букв пальцев не определить (карта пуста): кнопок упражнений нет.
    let model = FingerCardModel.make(reports: fingerReports(), fingerOf: [:])
    #expect(model.hasData)
    #expect(model.cells.allSatisfy { $0.drill == nil })
    #expect(model.cells.first { $0.finger == .leftPinky }?.tone == .weak)
    // Буквы только слабого пальца: кнопка только у него.
    let partial = FingerCardModel.make(reports: fingerReports(), fingerOf: ["й": .leftPinky])
    #expect(partial.cells.compactMap(\.drill) == [.accuracy])
}

@Test func fingerCardHasNoButtonWithoutOpenFingerLetters() {
    // Карта букв, ограниченная открытыми: у слабого мизинца ни одна буква не открыта — кнопки нет, у сильного есть.
    let open: Set<Character> = ["о", "в"]
    let model = FingerCardModel.make(reports: fingerReports(),
                                     fingerOf: allFingerLetters.filter { open.contains($0.key) })
    #expect(model.cells.first { $0.finger == .leftPinky }?.drill == nil)
    #expect(model.cells.first { $0.finger == .rightIndex }?.drill == .speed)
}

@Test func fingerCellWithoutDataShowsNoAccuracy() {
    // 10 нажатий, 2 ошибки: точность в отчёте есть (80%), но класс «мало данных» — в клетке «—».
    let few = FingerTraining.reports(presses: [.leftPinky: 10, .leftRing: 100], errors: [.leftPinky: 2],
                                     keyEwma: [:], fingerOf: [:], thresholdMs: 343)
    let model = FingerCardModel.make(reports: few, fingerOf: allFingerLetters)
    let pinky = model.cells.first { $0.finger == .leftPinky }!
    #expect(pinky.tone == .noData && pinky.report.accuracy != nil)
    #expect(pinky.accuracyText == "—")
    #expect(model.cells.first { $0.finger == .leftRing }?.accuracyText == Formatting.percent(1))
}

@Test func fingerRunKindHasFreshIdTitleAndAlert() {
    let a = RunKind.finger(FingerRun(language: .ru, finger: .leftPinky, drill: .accuracy))
    let b = RunKind.finger(FingerRun(language: .ru, finger: .leftPinky, drill: .accuracy))
    #expect(a.id != b.id)
    #expect(a.sidebarTitle == String(localized: "Пальцы идут"))
    #expect(a.replaceAlertTitle == String(localized: "Занятие по пальцу будет завершено. Начать новое занятие?"))
}

@MainActor @Test func fingerRunnerGoalFollowsDrill() {
    #expect(FingerRunnerView.goalText(.accuracy) == String(localized: "Цель: 0 ошибок"))
    #expect(FingerRunnerView.goalText(.speed) == nil)
}
