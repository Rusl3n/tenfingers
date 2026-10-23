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

    /// Нажатия и ошибки на клавишах мизинцев (по `keyCode`).
    public static func pinkyCounts(from result: ExerciseResult) -> (presses: Int, errors: Int) {
        let pinky = result.timings.filter {
            let finger = FingerMap.finger(for: $0.keyCode)
            return finger == .leftPinky || finger == .rightPinky
        }
        return (pinky.count, pinky.filter(\.hadError).count)
    }

    public static func ewma(_ old: Double?, _ sample: Double, alpha: Double = alpha) -> Double {
        guard let old else { return sample }
        return old + alpha * (sample - old)
    }

    public static func appendRecent(_ recent: [Bool], _ new: [Bool]) -> [Bool] {
        Array((recent + new).suffix(recentWindow))
    }
}
