import Foundation

public struct RhythmNote: Equatable, Sendable {
    public let index: Int
    public let time: TimeInterval
    public let character: Character
    public let lane: RhythmLane
    /// Номер слова в треке (режим «Слова»); у нот пробела и в режимах букв — `nil`.
    public let wordIndex: Int?
    /// Время полёта ноты от верха до линии; `nil` — как у уровня (у обычных уровней).
    public let scrollSeconds: Double?
    /// Множитель окон оценки ноты (1 — обычные окна; в бесконечном режиме на быстрых ступенях меньше 1).
    public let windowScale: Double

    public init(index: Int, time: TimeInterval, character: Character, lane: RhythmLane, wordIndex: Int?,
                scrollSeconds: Double? = nil, windowScale: Double = 1) {
        self.index = index
        self.time = time
        self.character = character
        self.lane = lane
        self.wordIndex = wordIndex
        self.scrollSeconds = scrollSeconds
        self.windowScale = windowScale
    }
}

public struct RhythmChart: Equatable, Sendable {
    public let notes: [RhythmNote]
    public let duration: TimeInterval
    public let level: RhythmLevel

    public init(notes: [RhythmNote], duration: TimeInterval, level: RhythmLevel) {
        self.notes = notes
        self.duration = duration
        self.level = level
    }

    /// Время полёта ноты: своё (бесконечный режим) или уровня.
    public func scrollSeconds(of note: RhythmNote) -> Double {
        note.scrollSeconds ?? level.scrollSeconds
    }
}

/// Расстановка нот по долям: каждая доля занята, время ноты — `leadIn + k · noteInterval`.
public enum RhythmChartBuilder {
    public static let trackSeconds: TimeInterval = 90
    public static let leadIn: TimeInterval = 2

    public static func build(
        source: RhythmNoteSource,
        level: RhythmLevel,
        fingers: [Character: Finger],
        seed: UInt64
    ) -> RhythmChart {
        if level.id == .endless { return buildEndless(source: source, level: level, fingers: fingers, seed: seed) }
        var generator = SeededGenerator(seed: seed)
        let interval = level.noteInterval
        var count = 0
        while leadIn + Double(count) * interval < trackSeconds { count += 1 }
        let picks = source.mode == .words
            ? wordPicks(source, fingers, count: count, &generator)
            : letterPicks(source, fingers, count: count, &generator)
        let notes = picks.enumerated().map { index, pick in
            RhythmNote(index: index, time: leadIn + Double(index) * interval, character: pick.character,
                       lane: pick.lane, wordIndex: pick.wordIndex)
        }
        return RhythmChart(notes: notes, duration: trackSeconds, level: level)
    }

    /// Бесконечный трек: время ноты `i` — `leadIn` + сумма интервалов предыдущих нот по их ступеням; скорость полёта
    /// и окна — по ступени самой ноты. Нот на `RhythmEndless.trackSeconds`.
    private static func buildEndless(
        source: RhythmNoteSource, level: RhythmLevel, fingers: [Character: Finger], seed: UInt64
    ) -> RhythmChart {
        var generator = SeededGenerator(seed: seed)
        var times: [TimeInterval] = []
        var time = leadIn
        while time < RhythmEndless.trackSeconds {
            times.append(time)
            time += 60 / Double(RhythmEndless.notesPerMinute(noteIndex: times.count - 1))
        }
        let picks = source.mode == .words
            ? wordPicks(source, fingers, count: times.count, &generator)
            : letterPicks(source, fingers, count: times.count, &generator)
        let notes = picks.enumerated().map { index, pick in
            let n = RhythmEndless.notesPerMinute(noteIndex: index)
            return RhythmNote(index: index, time: times[index], character: pick.character, lane: pick.lane,
                              wordIndex: pick.wordIndex, scrollSeconds: RhythmEndless.scrollSeconds(notesPerMinute: n),
                              windowScale: RhythmEndless.windowScale(notesPerMinute: n))
        }
        return RhythmChart(notes: notes, duration: RhythmEndless.trackSeconds, level: level)
    }

    private struct Pick {
        let character: Character
        let lane: RhythmLane
        let wordIndex: Int?
    }

    /// Случайные буквы набора; третья одинаковая подряд запрещена (выбирается другая).
    private static func letterPicks(
        _ source: RhythmNoteSource, _ fingers: [Character: Finger], count: Int, _ generator: inout SeededGenerator
    ) -> [Pick] {
        let pool = source.letters.compactMap { letter in
            RhythmLane.lane(for: letter, fingers: fingers).map { (letter: letter, lane: $0) }
        }
        guard !pool.isEmpty else { return [] }
        var picks: [Pick] = []
        for _ in 0..<count {
            var candidates = pool
            if let last = picks.last, picks.count >= 2, picks[picks.count - 2].character == last.character {
                let others = pool.filter { $0.letter != last.character }
                if !others.isEmpty { candidates = others }
            }
            let chosen = candidates[Int.random(in: 0..<candidates.count, using: &generator)]
            picks.append(Pick(character: chosen.letter, lane: chosen.lane, wordIndex: nil))
        }
        return picks
    }

    /// Слово целиком, затем нота пробела, затем следующее слово (одно слово подряд дважды не идёт);
    /// слово, не влезшее в трек, обрезается.
    private static func wordPicks(
        _ source: RhythmNoteSource, _ fingers: [Character: Finger], count: Int, _ generator: inout SeededGenerator
    ) -> [Pick] {
        let words = source.words.filter { word in
            !word.isEmpty && word.allSatisfy { $0 != " " && RhythmLane.lane(for: $0, fingers: fingers) != nil }
        }
        guard !words.isEmpty else { return [] }
        var picks: [Pick] = []
        var wordNumber = 0
        var previous: Int?
        while picks.count < count {
            var index = Int.random(in: 0..<words.count, using: &generator)
            if words.count > 1, index == previous { index = (index + 1) % words.count }
            previous = index
            for character in words[index] {
                let lane = RhythmLane.lane(for: character, fingers: fingers) ?? .space
                picks.append(Pick(character: character, lane: lane, wordIndex: wordNumber))
            }
            picks.append(Pick(character: " ", lane: .space, wordIndex: nil))
            wordNumber += 1
        }
        return Array(picks.prefix(count))
    }
}
