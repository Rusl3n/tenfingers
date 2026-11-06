import AppKit
import Foundation
import Testing
import TypingCore
@testable import TenFingers

private let root = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

/// Каждый экран итога получает ачивки: иначе звук ачивки играет, а карточки нет (так было у итога «Слабых мест»).
@Test func everyResultScreenReceivesNewAchievements() throws {
    try expectEveryResultScreen(passes: "newAchievements:")
}

/// То же для карточки «Полный огонь»: звук серии играет на экране итога, значит и карточка должна быть на каждом.
@Test func everyResultScreenReceivesFullFlame() throws {
    try expectEveryResultScreen(passes: "fullFlame:")
}

private func expectEveryResultScreen(passes argument: String) throws {
    let sources = root.appendingPathComponent("Sources/TenFingers")
    let files = try #require(FileManager.default.enumerator(at: sources, includingPropertiesForKeys: nil))
    var calls = 0
    var missing: [String] = []
    for case let url as URL in files where url.pathExtension == "swift" {
        let text = try String(contentsOf: url, encoding: .utf8)
        for name in ["RunSummaryView(", "LessonResultView(", "StepResultView("] {
            var rest = text[...]
            while let range = rest.range(of: name) {
                // Объявление `struct X: View {` не вызов.
                let before = rest[..<range.lowerBound].suffix(7)
                rest = rest[range.upperBound...]
                if before.hasSuffix("struct ") { continue }
                calls += 1
                // Аргументы вызова — до закрывающей скобки на том же уровне.
                var depth = 1
                var end = rest.startIndex
                while depth > 0, end < rest.endIndex {
                    if rest[end] == "(" { depth += 1 } else if rest[end] == ")" { depth -= 1 }
                    end = rest.index(after: end)
                }
                if !rest[..<end].contains(argument) { missing.append("\(url.lastPathComponent): \(name)") }
            }
        }
    }
    #expect(calls >= 5)
    #expect(missing.isEmpty, "экраны итога без `\(argument)`: \(missing)")
}

// MARK: - «Ускорение»

/// Плашка над текстом шагов «Ускорения» и строка итога урока (решение 16): единица — из настроек.
@Test func speedupBannerAndOutcomeLines() {
    #expect(LessonRunPlan.speedupBanner(reference: 142, unit: .cpm) == "Обгоните себя: 142 зн/мин → цель 149 зн/мин")
    #expect(LessonRunPlan.speedupBanner(reference: 142, unit: .wpm) == "Обгоните себя: 28 WPM → цель 30 WPM")
    #expect(LessonResultView.speedupText(.beaten(percent: 6), unit: .cpm) == "Рекорд побит: +6%")
    #expect(LessonResultView.speedupText(.short(cpm: 4), unit: .cpm) == "До рекорда не хватило 4 зн/мин")
    // Нехватка в WPM округляется вверх: недостающее не выглядит нулём.
    #expect(LessonResultView.speedupText(.short(cpm: 4), unit: .wpm) == "До рекорда не хватило 1 WPM")
}

/// Итог повтора шага — с номером шага в плане («4. Слова»), как строка шага на карте курса.
@Test func stepResultTitleHasStepNumber() {
    let words = ExerciseKind.words.localizedTitle
    #expect(StepTitle.numbered(3, words) == "4. \(words)")
}

/// Повтор одной проверки «Ускорения» показывает тот же итог против ориентира, что и весь урок: он считается
/// только для проверки и только когда ориентир есть (у остальных уроков и шагов его нет).
@Test func speedupOutcomeForReplayedCheck() {
    #expect(LessonRunPlan.speedupOutcome(kind: .check, cpm: 150, reference: 142) == .beaten(percent: 6))
    #expect(LessonRunPlan.speedupOutcome(kind: .check, cpm: 138, reference: 142) == .short(cpm: 4))
    #expect(LessonRunPlan.speedupOutcome(kind: .check, cpm: 150, reference: nil) == nil)
    #expect(LessonRunPlan.speedupOutcome(kind: .sprint, cpm: 150, reference: 142) == nil)
    // Текст на экране итога шага — тот же, что у итога урока.
    #expect(LessonResultView.speedupText(.beaten(percent: 6), unit: .cpm) == "Рекорд побит: +6%")
}

// MARK: - Жёсткий допуск ошибок в шаге (8a)

@Test func interimOverLimitHasNoNextAndRetryIsPrimary() {
    let over = StepInterim(errors: 5, limit: 4)
    #expect(over.overLimit)
    #expect(!over.showsNext)
    #expect(over.showsRetry)
    #expect(over.toleranceLine == "Ошибок 5 — допустимо не больше 4")
}

@Test func interimWithinLimitIsAsBefore() {
    for model in [StepInterim(errors: 4, limit: 4), StepInterim(errors: 9, limit: nil)] {
        #expect(!model.overLimit)
        #expect(model.showsNext)
        #expect(!model.showsRetry)
        #expect(model.toleranceLine == nil)
    }
}

@Test func errorCounterTextAndColor() {
    #expect(ErrorCounter.text(errors: 2, limit: 3) == "Ошибки: 2 из 3")
    #expect(!ErrorCounter.isOver(errors: 3, limit: 3))
    #expect(ErrorCounter.isOver(errors: 4, limit: 3))
}

@Test func checkIsUnavailableWhileAStepIsOverLimit() {
    var pass = LessonPass()
    #expect(pass.checkAvailable)
    #expect(pass.entry(requested: 3, lastIndex: 3) == 3)
    pass.record(step: 2, passed: false)
    #expect(!pass.checkAvailable)
    #expect(pass.entry(requested: 3, lastIndex: 3) == 2)
    #expect(pass.entry(requested: 1, lastIndex: 3) == 1)
    pass.record(step: 2, passed: true)
    #expect(pass.checkAvailable)
    #expect(pass.entry(requested: 3, lastIndex: 3) == 3)
}

// MARK: - Разбор шага и урока (8a)

private func engineResult(_ text: String, wrong: Set<Int> = [], slowRange: Range<Int>? = nil) -> ExerciseResult {
    var engine = TypingEngine(text: text)
    var time = 0.0
    for (index, ch) in text.enumerated() {
        if wrong.contains(index) {
            time += 0.05
            _ = engine.handle(Keystroke(character: "~", keyCode: 0, timestamp: time))
        }
        time += (slowRange?.contains(index) ?? false ? 400.0 : 100.0) / 1000
        _ = engine.handle(Keystroke(character: ch, keyCode: 0, timestamp: time))
    }
    return ExerciseResult(engine: engine, mode: .course, language: .ru, lessonId: "l", startedAt: .distantPast,
                          endedAt: .distantPast, hintLevel: .full)
}

private let reviewText = String(repeating: "abcd ", count: 12) // 60 знаков

@Test func stepScreenGivesReviewLinesInOrder() {
    let result = engineResult(reviewText, slowRange: 20..<40)
    let segments = SpeedSegments.split(text: reviewText, timings: result.timings)
    let screen = StepReviewScreen.make(text: reviewText, result: result, targetCpm: nil, segments: segments)
    #expect(screen.lines.map(\.key) == ["review.clean", "review.slowest"])
    #expect(screen.lines[1].args == ["abcd abcd abcd abcd"])
    #expect(screen.showsChart)
    #expect(screen.slow == SpeedSegments.slow(segments))
}

@Test func stepScreenWithoutSegmentsHidesChartButKeepsLines() {
    let t = String(repeating: "aabbccdd ", count: 6)
    let result = engineResult(t, wrong: [0, 9, 18, 2])
    let screen = StepReviewScreen.make(text: t, result: result, targetCpm: nil, segments: nil)
    #expect(!screen.showsChart)
    #expect(screen.segments == nil && screen.slow.isEmpty)
    #expect(screen.lines == [ReviewLine(key: "review.letters", args: ["a", "b"])])
    // Один отрезок — график бессмыслен.
    let one = StepReviewScreen.make(text: t, result: result, targetCpm: nil,
                                    segments: [SpeedSegment(start: 0, end: 54, cpm: 200)])
    #expect(!one.showsChart)
}

private let day = Date(timeIntervalSinceReferenceDate: 800_000_000)
private func record(_ step: Int, at offset: Double, cpm: Double = 200, errors: Int = 0, completed: Bool = true,
                    presses: [Finger: Int] = [:], wrong: [Finger: Int] = [:],
                    segments: [SpeedSegment]? = nil) -> PassRecord {
    PassRecord(stepIndex: step, startedAt: day.addingTimeInterval(offset), completed: completed, cpm: cpm,
               errorCount: errors, fingerPresses: presses, fingerErrors: wrong, segments: segments)
}

@Test func lessonReviewUsesOnlyCurrentPassSteps() {
    let records = [
        record(0, at: -1000, cpm: 999),                 // прошлый проход
        record(0, at: 10, cpm: 200), record(1, at: 20, cpm: 250, errors: 2),
        record(1, at: 30, cpm: 300),                    // повтор шага: берётся последняя запись
        record(2, at: 40, cpm: 220, completed: false),  // брошенный шаг не считается
    ]
    let model = LessonReviewModel.make(records: records, letters: [1: ["a": 2]], resumeStart: 0, passStart: day)
    #expect(model.stepSpeeds == [.init(index: 0, cpm: 200), .init(index: 1, cpm: 300)])
    #expect(model.review.bestStep == 1)
    #expect(model.review.cleanSteps == [0, 1])
}

@Test func lessonReviewKeepsEarlierStepsOfAResumedPass() {
    let records = [record(0, at: -5000, cpm: 150), record(1, at: -4000, cpm: 160),
                   record(1, at: -9000, cpm: 999), record(2, at: 10, cpm: 170)]
    let model = LessonReviewModel.make(records: records, letters: [:], resumeStart: 2, passStart: day)
    #expect(model.stepSpeeds.map(\.cpm) == [150, 160, 170])
}

@Test func lessonReviewAdviceAndFinalSegments() {
    let segments = [SpeedSegment(start: 0, end: 20, cpm: 100), SpeedSegment(start: 20, end: 40, cpm: 200)]
    let records = [
        record(0, at: 10, errors: 3, presses: [.leftRing: 12], wrong: [.leftRing: 3]),
        record(1, at: 20, errors: 1, presses: [.leftRing: 8, .rightIndex: 30], wrong: [.leftRing: 0, .rightIndex: 1],
               segments: segments),
    ]
    let model = LessonReviewModel.make(records: records, letters: [0: ["x": 2, " ": 9], 1: ["y": 1]], resumeStart: 0,
                                       passStart: day)
    #expect(model.review.finger == .leftRing) // 3 из 20 — 85 %
    #expect(model.review.advice == .finger(.leftRing))
    #expect(model.review.letters == ["x", "y"])
    #expect(model.finalSegments == segments)
    let clean = LessonReviewModel.make(records: [record(0, at: 10)], letters: [:], resumeStart: 0, passStart: day)
    #expect(clean.review.advice == .nextLesson && clean.finalSegments == nil)
    #expect(LessonReviewModel.make(records: [], letters: [:], resumeStart: 0, passStart: day).stepSpeeds.isEmpty)
}

@Test func adviceLeadsToTheSameRunsAsTheCards() {
    let next = LessonRun(language: .ru, lessonId: "l2")
    guard case .finger(let run)? = ReviewDestination.run(for: .finger(.leftRing), language: .ru, next: next) else {
        Issue.record("палец должен открыть «Пальцы»"); return
    }
    #expect(run.finger == .leftRing && run.language == .ru && run.drill == .accuracy && run.planSlot == nil)
    guard case .weakSpots(let weak)? = ReviewDestination.run(for: .weakSpots, language: .en, next: next) else {
        Issue.record("слабые места"); return
    }
    #expect(weak.language == .en && weak.focus == nil)
    #expect(ReviewDestination.run(for: .nextLesson, language: .ru, next: next) == .lesson(next))
    #expect(ReviewDestination.run(for: .nextLesson, language: .ru, next: nil) == nil)
    guard case .errorWords(let words)? = ReviewDestination.run(for: .errorWords, language: .ru, next: next) else {
        Issue.record("«Слова с ошибками» — занятие слов с ошибками"); return
    }
    #expect(words.language == .ru && words.planSlot == nil)
    #expect(ReviewDestination.title(for: .errorWords) == "Слова с ошибками")
}

/// Все ключи `review.*` ядра переведены на оба языка приложения (`ReviewLine` локализует приложение).
@Test func everyReviewKeyHasRuAndEnStrings() throws {
    let core = root.appendingPathComponent("Sources/TypingCore/Course/ExerciseReview.swift")
    let source = try String(contentsOf: core, encoding: .utf8)
    let keys = Set(source.matches(of: /"(review\.[A-Za-z]+)"/).map { String($0.output.1) })
    #expect(keys.count >= 6)
    for lang in ["ru", "en"] {
        let url = root.appendingPathComponent("Localization/\(lang).lproj/Localizable.strings")
        let table = try #require(try PropertyListSerialization.propertyList(
            from: Data(contentsOf: url), format: nil) as? [String: String])
        for key in keys { #expect(!(table[key] ?? "").isEmpty, "\(lang): нет \(key)") }
    }
    #expect(ReviewText.text(ReviewLine(key: "review.accuracy", args: ["99"]), template: "Точность %@%%") == "Точность 99%")
    #expect(ReviewText.text(ReviewLine(key: "review.letters", args: ["a", "b"]), template: "Буквы: %@") == "Буквы: a, b")
}

@Test func reviewSymbolsExist() {
    for name in ["chart.bar.fill", "chevron.right"] { #expect(NSImage(systemSymbolName: name, accessibilityDescription: nil) != nil) }
}

@Test func lessonReviewAdvisesErrorWordsWhenAvailable() {
    let records = [record(0, at: 10, errors: 2)]
    let with = LessonReviewModel.make(records: records, letters: [0: ["a": 2]], resumeStart: 0, passStart: day,
                                      errorWordsAvailable: true)
    #expect(with.review.advice == .errorWords)
    let without = LessonReviewModel.make(records: records, letters: [0: ["a": 2]], resumeStart: 0, passStart: day)
    #expect(without.review.advice == .weakSpots)
}
