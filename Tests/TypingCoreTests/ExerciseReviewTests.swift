import Foundation
import Testing
@testable import TypingCore

private func result(_ text: String, wrong: Set<Int> = [], ms: Double = 100, slowRange: Range<Int>? = nil,
                    slowMs: Double = 400) -> ExerciseResult {
    var engine = TypingEngine(text: text)
    var time = 0.0
    for (index, ch) in text.enumerated() {
        if wrong.contains(index) {
            time += 0.05
            _ = engine.handle(Keystroke(character: "~", keyCode: 0, timestamp: time))
        }
        time += (slowRange?.contains(index) ?? false ? slowMs : ms) / 1000
        _ = engine.handle(Keystroke(character: ch, keyCode: 0, timestamp: time))
    }
    return ExerciseResult(engine: engine, mode: .course, language: .ru, lessonId: "l", startedAt: .distantPast,
                          endedAt: .distantPast, hintLevel: .full)
}

private func review(_ text: String, _ r: ExerciseResult, target: Double? = nil) -> StepReview {
    ExerciseReview.step(text: text, result: r, targetCpm: target,
                        segments: SpeedSegments.split(text: text, timings: r.timings))
}

private let text = String(repeating: "abcd ", count: 12) // 60 знаков

@Test func cleanStepIsGood() {
    #expect(review(text, result(text)).good?.key == "review.clean")
}

@Test func highAccuracyIsGood() {
    let long = String(repeating: "abcd ", count: 40) // 200 знаков, 2 ошибки = 99 %
    let r = result(long, wrong: [3, 50])
    #expect(review(long, r).good == ReviewLine(key: "review.accuracy", args: ["99"]))
}

@Test func fasterThanTargetThenEvenPace() {
    let r = result(text, wrong: [1, 2, 3, 4, 5]) // точность ~92 %
    #expect(review(text, r, target: 100).good?.key == "review.fasterThanTarget")
    #expect(review(text, r, target: 10_000).good?.key == "review.evenPace")
}

@Test func slowSegmentGivesSlowWords() {
    let r = result(text, slowRange: 20..<40)
    let step = review(text, r)
    #expect(step.slowWords == "abcd abcd abcd abcd")
    #expect(step.trouble == [ReviewLine(key: "review.slowest", args: ["abcd abcd abcd abcd"])])
    #expect(step.good == ReviewLine(key: "review.clean"))
}

@Test func troubleLettersByCountDescendingUpToThree() {
    let word = "aabbccdd "
    let t = String(repeating: word, count: 6)
    // a: 3 ошибки, b: 2, c: 1, d: 1 (d отсекается тай-брейком).
    let r = result(t, wrong: [0, 9, 18, 2, 11, 4])
    let step = review(t, r)
    #expect(step.slowWords == nil)
    #expect(step.trouble == [ReviewLine(key: "review.letters", args: ["a", "b", "c"])])
}

private func summary(_ i: Int, _ cpm: Double, _ errors: Int, _ by: [Character: Int] = [:]) -> LessonStepSummary {
    LessonStepSummary(stepIndex: i, cpm: cpm, errorCount: errors, errorsByCharacter: by)
}

@Test func lessonReviewBestAndClean() {
    let steps = [summary(0, 200, 0), summary(1, 300, 2, ["a": 2]), summary(2, 250, 0)]
    let review = ExerciseReview.lesson(steps: steps, fingerPresses: [:], fingerErrors: [:], errorWordsAvailable: false)
    #expect(review.bestStep == 1 && review.cleanSteps == [0, 2])
    #expect(review.letters == ["a"] && review.finger == nil)
    #expect(ExerciseReview.lesson(steps: [], fingerPresses: [:], fingerErrors: [:], errorWordsAvailable: false)
        .bestStep == nil)
}

@Test func lessonAdviceOrder() {
    let steps = [summary(0, 100, 3, ["x": 2, "y": 1, "z": 1, "w": 1])]
    let weak = ExerciseReview.lesson(steps: steps, fingerPresses: [.leftRing: 20, .rightIndex: 50],
                                     fingerErrors: [.leftRing: 2, .rightIndex: 3], errorWordsAvailable: true)
    #expect(weak.finger == .leftRing && weak.advice == .finger(.leftRing)) // 90 % против 94 %
    #expect(weak.letters.count == 3 && weak.letters.first == "x")

    let nine = ExerciseReview.lesson(steps: steps, fingerPresses: [.leftRing: 9], fingerErrors: [.leftRing: 5],
                                     errorWordsAvailable: false)
    #expect(nine.finger == nil && nine.advice == .weakSpots)
    let words = ExerciseReview.lesson(steps: steps, fingerPresses: [.leftRing: 100], fingerErrors: [.leftRing: 5],
                                      errorWordsAvailable: true)
    #expect(words.finger == nil && words.advice == .errorWords) // 95 % — не ниже порога
    let next = ExerciseReview.lesson(steps: [summary(0, 100, 0)], fingerPresses: [:], fingerErrors: [:],
                                     errorWordsAvailable: true)
    #expect(next.advice == .nextLesson)
}

@Test func whitespaceIsNeverATroubleLetter() {
    let steps = [summary(0, 100, 9, [" ": 5, "\n": 3, "a": 1])]
    let only = ExerciseReview.lesson(steps: steps, fingerPresses: [:], fingerErrors: [:], errorWordsAvailable: false)
    #expect(only.letters == ["a"])
    let blank = ExerciseReview.lesson(steps: [summary(0, 100, 8, [" ": 5, "\n": 3])], fingerPresses: [:],
                                      fingerErrors: [:], errorWordsAvailable: false)
    #expect(blank.letters.isEmpty && blank.advice == .nextLesson)
    // Шаг: ошибки на пробелах не дают строки «буквы».
    let t = String(repeating: "abcd ", count: 12)
    let r = result(t, wrong: [4, 9, 14])
    #expect(r.errorsByCharacter[" "] != nil)
    #expect(review(t, r).trouble.isEmpty)
}

@Test func thumbIsNeverTheWorstFinger() {
    let steps = [summary(0, 100, 3, ["x": 2])]
    let review = ExerciseReview.lesson(steps: steps, fingerPresses: [.thumb: 20, .leftRing: 20],
                                       fingerErrors: [.thumb: 10, .leftRing: 2], errorWordsAvailable: false)
    #expect(review.finger == .leftRing) // у большого пальца карточки «Пальцы» нет
    let onlyThumb = ExerciseReview.lesson(steps: steps, fingerPresses: [.thumb: 20], fingerErrors: [.thumb: 10],
                                          errorWordsAvailable: false)
    #expect(onlyThumb.finger == nil && onlyThumb.advice == .weakSpots)
}
