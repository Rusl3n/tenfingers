import Foundation

/// Рекомендация «Куда дальше» (§2.3).
public enum ReviewAdvice: Equatable, Sendable {
    case finger(Finger), weakSpots, errorWords, nextLesson
}

/// Строка разбора: ключ локализации (`review.*`) и аргументы; текст собирает приложение.
public struct ReviewLine: Equatable, Sendable {
    public let key: String
    public let args: [String]

    public init(key: String, args: [String] = []) {
        self.key = key
        self.args = args
    }
}

public struct StepReview: Equatable, Sendable {
    public let good: ReviewLine?
    public let trouble: [ReviewLine]
    /// Слова самого медленного (из медленных) отрезка — для подсказки в графике.
    public let slowWords: String?
}

public struct LessonStepSummary: Equatable, Sendable {
    public let stepIndex: Int
    public let cpm: Double
    public let errorCount: Int
    public let errorsByCharacter: [Character: Int]

    public init(stepIndex: Int, cpm: Double, errorCount: Int, errorsByCharacter: [Character: Int]) {
        self.stepIndex = stepIndex
        self.cpm = cpm
        self.errorCount = errorCount
        self.errorsByCharacter = errorsByCharacter
    }
}

public struct LessonReview: Equatable, Sendable {
    public let bestStep: Int?
    public let cleanSteps: [Int]
    public let letters: [Character]
    public let finger: Finger?
    public let advice: ReviewAdvice
}

/// Правила разбора шага и урока (§2.2–2.3): без генерации текста, только ключи и аргументы.
public enum ExerciseReview {
    public static let goodAccuracy = 0.98
    public static let maxLetters = 3
    public static let fingerMinimumPresses = 10
    public static let fingerAccuracyBelow = 0.95

    public static func step(text: String, result: ExerciseResult, targetCpm: Double?,
                            segments: [SpeedSegment]) -> StepReview {
        let chars = Array(text)
        let slow = SpeedSegments.slow(segments)
        let slowest = slow.min { (segments[$0].cpm ?? 0) < (segments[$1].cpm ?? 0) }
        let slowWords = slowest.flatMap { index -> String? in
            let segment = segments[index]
            guard segment.start >= 0, segment.end <= chars.count, segment.start < segment.end else { return nil }
            let words = String(chars[segment.start..<segment.end]).trimmingCharacters(in: .whitespaces)
            return words.isEmpty ? nil : words
        }

        let good: ReviewLine?
        if result.errorCount == 0 {
            good = ReviewLine(key: "review.clean")
        } else if result.accuracy >= goodAccuracy {
            good = ReviewLine(key: "review.accuracy", args: ["\(Int((result.accuracy * 100).rounded()))"])
        } else if let targetCpm, result.cpm >= targetCpm {
            good = ReviewLine(key: "review.fasterThanTarget")
        } else if SpeedSegments.isEven(segments) {
            good = ReviewLine(key: "review.evenPace")
        } else {
            good = nil
        }

        var trouble: [ReviewLine] = []
        if let slowWords {
            trouble = [ReviewLine(key: "review.slowest", args: [slowWords])]
        } else {
            let letters = topLetters(result.errorsByCharacter)
            if !letters.isEmpty { trouble = [ReviewLine(key: "review.letters", args: letters.map(String.init))] }
        }
        return StepReview(good: good, trouble: trouble, slowWords: slowWords)
    }

    public static func lesson(steps: [LessonStepSummary], fingerPresses: [Finger: Int], fingerErrors: [Finger: Int],
                              errorWordsAvailable: Bool) -> LessonReview {
        let best = steps.max { $0.cpm < $1.cpm }?.stepIndex
        let clean = steps.filter { $0.errorCount == 0 }.map(\.stepIndex)
        let letters = topLetters(steps.reduce(into: [:]) { total, step in
            total.merge(step.errorsByCharacter, uniquingKeysWith: +)
        })
        let finger = worstFinger(presses: fingerPresses, errors: fingerErrors)
        let advice: ReviewAdvice
        if let finger {
            advice = .finger(finger)
        } else if !letters.isEmpty {
            advice = errorWordsAvailable ? .errorWords : .weakSpots
        } else {
            advice = .nextLesson
        }
        return LessonReview(bestStep: best, cleanSteps: clean, letters: letters, finger: finger, advice: advice)
    }

    private static func topLetters(_ errors: [Character: Int]) -> [Character] {
        errors.filter { $0.value > 0 && !$0.key.isWhitespace }
            .sorted { $0.value != $1.value ? $0.value > $1.value : String($0.key) < String($1.key) }
            .prefix(maxLetters).map(\.key)
    }

    private static func worstFinger(presses: [Finger: Int], errors: [Finger: Int]) -> Finger? {
        let candidates = presses.compactMap { finger, count -> (Finger, Double)? in
            guard finger != .thumb, count >= fingerMinimumPresses else { return nil }
            let accuracy = 1 - Double(errors[finger, default: 0]) / Double(count)
            return accuracy < fingerAccuracyBelow ? (finger, accuracy) : nil
        }
        return candidates.min { $0.1 != $1.1 ? $0.1 < $1.1 : $0.0.rawValue < $1.0.rawValue }?.0
    }
}
