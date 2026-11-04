import Foundation

public enum RhythmBeatStyle: String, CaseIterable, Sendable {
    case pulse, groove, drive
}

/// Бит для ритм-игры: один такт 4/4, синтез кодом (моно, Float, −1…1), детерминированный.
public enum BeatSynth {
    public static func loop(style: RhythmBeatStyle, bpm: Int, sampleRate: Double = SoundSynth.sampleRate) -> [Float] {
        let beat = 60.0 / Double(bpm)
        let count = Int((4 * beat * sampleRate).rounded())
        guard count > 0 else { return [] }
        var buffer = [Double](repeating: 0, count: count)

        /// Кладёт голос в буфер с позиции `beatPosition` долей; хвост за концом такта заворачивается в начало петли.
        func place(_ voice: [Double], at beatPosition: Double, gain: Double) {
            let start = Int((beatPosition * beat * sampleRate).rounded())
            for (offset, value) in voice.enumerated() {
                buffer[(start + offset) % count] += gain * value
            }
        }

        let kick = kickVoice(sampleRate)
        let snare = snareVoice(sampleRate)
        let hat = hatVoice(sampleRate)
        let bass = bassVoice(sampleRate)

        switch style {
        case .pulse:
            for b in 0..<4 { place(kick, at: Double(b), gain: 0.7) }
            for e in 0..<8 { place(hat, at: Double(e) / 2, gain: e % 2 == 1 ? 0.35 : 0.2) }
        case .groove:
            for b in [0, 2] { place(kick, at: Double(b), gain: 0.7) }
            for b in [1, 3] { place(snare, at: Double(b), gain: 0.6) }
            for e in 0..<8 { place(hat, at: Double(e) / 2, gain: e % 2 == 1 ? 0.3 : 0.18) }
            place(bass, at: 0, gain: 0.5)
        case .drive:
            for b in 0..<4 {
                place(kick, at: Double(b), gain: 0.7)
                place(bass, at: Double(b), gain: 0.4)
            }
            for s in 0..<16 { place(hat, at: Double(s) / 4, gain: s % 2 == 1 ? 0.28 : 0.16) }
        }

        return buffer.map { Float(max(-1, min(1, 0.85 * $0))) }
    }

    private static func voice(ms: Int, _ sampleRate: Double, _ wave: (_ t: Double, _ index: Int) -> Double) -> [Double] {
        let count = Int(sampleRate * Double(ms) / 1000)
        let fade = max(1, Int(sampleRate * 0.002))
        return (0..<count).map { index in
            var value = wave(Double(index) / sampleRate, index)
            if index < 16 { value *= Double(index) / 16 }          // без щелчка в начале
            if index >= count - fade { value *= Double(count - 1 - index) / Double(fade) }
            return value
        }
    }

    private static func kickVoice(_ sampleRate: Double) -> [Double] {
        var phase = 0.0
        return voice(ms: 220, sampleRate) { t, _ in
            let frequency = 45 + 90 * exp(-t / 0.03)
            phase += 2 * .pi * frequency / sampleRate
            return sin(phase) * exp(-t / 0.08)
        }
    }

    private static func snareVoice(_ sampleRate: Double) -> [Double] {
        var rng = SeededGenerator(seed: 21)
        return voice(ms: 160, sampleRate) { t, _ in
            let noise = Double.random(in: -1...1, using: &rng)
            return 0.7 * noise * exp(-t / 0.04) + 0.4 * sin(2 * .pi * 190 * t) * exp(-t / 0.05)
        }
    }

    private static func hatVoice(_ sampleRate: Double) -> [Double] {
        var rng = SeededGenerator(seed: 33)
        var previous = 0.0
        return voice(ms: 45, sampleRate) { t, _ in
            let noise = Double.random(in: -1...1, using: &rng)
            let high = noise - previous                             // разность — грубый фильтр верхних частот
            previous = noise
            return 0.5 * high * exp(-t / 0.012)
        }
    }

    private static func bassVoice(_ sampleRate: Double) -> [Double] {
        voice(ms: 260, sampleRate) { t, _ in
            0.8 * sin(2 * .pi * 55 * t) * exp(-t / 0.12)
        }
    }
}
