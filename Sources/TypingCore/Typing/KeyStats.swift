/// Данные одного упражнения по одному символу.
public struct KeyStatSample: Equatable, Sendable {
    public var keyCode: UInt16?
    /// По одному значению на появление символа: `true`, если на этой позиции была ошибка.
    public var outcomes: [Bool] = []
    public var intervalsMs: [Double] = []

    public init() {}
}

public enum KeyStats {
    public static let alpha = 0.1
    public static let recentWindow = 50

    public static func samples(from result: ExerciseResult) -> [Character: KeyStatSample] {
        var samples: [Character: KeyStatSample] = [:]
        for timing in result.timings where timing.character != " " {
            var sample = samples[timing.character, default: KeyStatSample()]
            sample.keyCode = timing.keyCode
            sample.outcomes.append(timing.hadError)
            if let ms = timing.intervalMs { sample.intervalsMs.append(ms) }
            samples[timing.character] = sample
        }
        return samples
    }

    /// Пары подряд идущих букв (без пробелов и знаков), в нижнем регистре. Исход и интервал — по второй букве.
    public static func bigramSamples(from result: ExerciseResult) -> [String: KeyStatSample] {
        var samples: [String: KeyStatSample] = [:]
        for (previous, current) in zip(result.timings, result.timings.dropFirst())
        where previous.character.isLetter && current.character.isLetter {
            let key = (String(previous.character) + String(current.character)).lowercased()
            var sample = samples[key, default: KeyStatSample()]
            sample.outcomes.append(current.hadError)
            if let ms = current.intervalMs { sample.intervalsMs.append(ms) }
            samples[key] = sample
        }
        return samples
    }

    /// Нажатия и ошибки на клавишах мизинцев (по `keyCode`).
    public static func pinkyCounts(from result: ExerciseResult) -> (presses: Int, errors: Int) {
        let pinky = result.timings.filter {
            let finger = FingerMap.finger(for: $0.keyCode)
            return finger == .leftPinky || finger == .rightPinky
        }
        return (pinky.count, pinky.filter(\.hadError).count)
    }

    /// Нажатия и ошибки по пальцам (по `keyCode`, пробел — `thumb`); клавиши без пальца пропускаются.
    /// Палец с нажатиями есть в обоих словарях (ошибок может быть 0).
    public static func fingerCounts(from result: ExerciseResult) -> (presses: [Finger: Int], errors: [Finger: Int]) {
        var presses: [Finger: Int] = [:]
        var errors: [Finger: Int] = [:]
        for timing in result.timings {
            guard let finger = FingerMap.finger(for: timing.keyCode) else { continue }
            presses[finger, default: 0] += 1
            errors[finger, default: 0] += timing.hadError ? 1 : 0
        }
        return (presses, errors)
    }

    /// «ё» и «Ё» (для `yoCorrect` и для подсчёта прежних нажатий по `KeyStat`).
    public static let yoLetters: Set<Character> = ["ё", "Ё"]

    /// «ё» и «Ё» без ошибки.
    public static func yoCorrect(from result: ExerciseResult) -> Int {
        result.timings.filter { yoLetters.contains($0.character) && !$0.hadError }.count
    }

    public static func ewma(_ old: Double?, _ sample: Double, alpha: Double = alpha) -> Double {
        guard let old else { return sample }
        return old + alpha * (sample - old)
    }

    public static func appendRecent(_ recent: [Bool], _ new: [Bool]) -> [Bool] {
        Array((recent + new).suffix(recentWindow))
    }
}
