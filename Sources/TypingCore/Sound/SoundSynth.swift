import Foundation

public enum SoundEvent: String, CaseIterable, Sendable {
    case keyClick, error, exerciseDone, lessonDone, achievement, streak
}

/// Звуки, синтезированные кодом (моно, Float, −1…1), без файлов и лицензий.
public enum SoundSynth {
    public static let sampleRate = 44_100.0

    public static func samples(for event: SoundEvent) -> [Float] {
        switch event {
        case .keyClick:
            var rng = SeededGenerator(seed: 7)
            return render(ms: 18) { t, _ in
                let noise = Double.random(in: -1...1, using: &rng)
                return 0.55 * noise * exp(-t / 0.003) + 0.35 * sin(2 * .pi * 2000 * t) * exp(-t / 0.004)
            }
        case .error:
            return render(ms: 140) { t, _ in
                0.8 * (0.7 * sin(2 * .pi * 110 * t) + 0.3 * sin(2 * .pi * 165 * t)) * exp(-t / 0.04)
            }
        case .exerciseDone:
            return notes([(660, 90), (880, 140)], decay: 0.06)
        case .lessonDone:
            return notes([(523.25, 110), (659.25, 110), (783.99, 260)], decay: 0.09)
        case .achievement:
            return notes([(783.99, 70), (987.77, 70), (1174.66, 70), (1567.98, 220)], decay: 0.07)
        case .streak:
            var rng = SeededGenerator(seed: 11)
            var low = 0.0
            return render(ms: 320) { t, total in
                let noise = Double.random(in: -1...1, using: &rng)
                low += 0.08 * (noise - low)                  // однополюсный фильтр — «шорох»
                let envelope = sin(.pi * t / total)          // нарастание и спад
                return 0.9 * low * 4 * envelope * envelope + 0.25 * sin(2 * .pi * (220 + 440 * t / total) * t) * envelope
            }
        }
    }

    /// Последовательность нот (частота Гц, длительность мс) с экспоненциальным затуханием каждой.
    private static func notes(_ list: [(Double, Int)], decay: Double) -> [Float] {
        list.flatMap { frequency, ms in
            render(ms: ms) { t, _ in 0.6 * sin(2 * .pi * frequency * t) * exp(-t / decay) }
        }
    }

    /// Рендерит `ms` миллисекунд; на краях плавные фейды по 2 мс, чтобы не было щелчков.
    private static func render(ms: Int, _ wave: (_ t: Double, _ total: Double) -> Double) -> [Float] {
        let count = Int(sampleRate * Double(ms) / 1000)
        let total = Double(count) / sampleRate
        let fade = Int(sampleRate * 0.002)
        return (0..<count).map { index in
            let t = Double(index) / sampleRate
            var value = wave(t, total)
            if index < fade { value *= Double(index) / Double(fade) }
            if index >= count - fade { value *= Double(count - 1 - index) / Double(fade) }
            return Float(max(-1, min(1, value)))
        }
    }
}
