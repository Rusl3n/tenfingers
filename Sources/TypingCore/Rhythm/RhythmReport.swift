import Foundation

public enum RhythmGrade: String, Codable, Sendable {
    case s = "S", a = "A", b = "B", c = "C", d = "D"
}

/// Разбор захода (§3.6): оценка буквой, буквы, путаницы, пальцы. Все доли — от оценённых нот.
public struct RhythmReport: Codable, Equatable, Sendable {
    public struct LetterLine: Codable, Equatable, Sendable {
        public let character: String
        public let notes: Int
        public let accuracy: Double
        /// Средний сдвиг в мс; отрицательный — рано.
        public let meanOffsetMs: Double

        public init(character: String, notes: Int, accuracy: Double, meanOffsetMs: Double) {
            self.character = character
            self.notes = notes
            self.accuracy = accuracy
            self.meanOffsetMs = meanOffsetMs
        }
    }

    public struct Confusion: Codable, Equatable, Sendable {
        public let expected: String
        public let pressed: String
        public let count: Int

        public init(expected: String, pressed: String, count: Int) {
            self.expected = expected
            self.pressed = pressed
            self.count = count
        }
    }

    public static let minLetterNotes = 3
    public static let topLetters = 3
    /// Средний сдвиг (мс, по модулю), с которого буква с точностью 100% всё же слабая: в среднем вне окна «Точно».
    public static let weakOffsetMs = RhythmJudge.perfectWindow * 1000
    public static let topConfusions = 5

    /// perfect, good, early, late, wrongKey, skipped — все шесть ключей.
    public let counts: [String: Int]
    public let accuracy: Double
    public let grade: RhythmGrade
    public let strong: [LetterLine]
    public let weak: [LetterLine]
    public let letters: [LetterLine]
    public let confusions: [Confusion]
    /// Доля miss по дорожкам пальцев; ключ — `Finger.rawValue`. Дорожки без оценённых нот не входят.
    public let fingerMissRate: [String: Double]
    /// Оценки по дорожкам пальцев: ключ — `Finger.rawValue`, внутри — те же шесть ключей, что у `counts`
    /// (только ненулевые). `nil` — разбор записан до появления поля.
    public let fingerCounts: [String: [String: Int]]?
    public let maxMissStreak: Int
    /// Бесконечный режим: сколько трека продержались — время последней оценённой ноты минус время первой, с.
    /// `nil` — у обычных уровней и у разбора, записанного до появления поля.
    public let survivedSeconds: Double?
    /// Бесконечный режим: темп (нот в минуту) на ступени последней оценённой ноты. `nil` — как у `survivedSeconds`.
    public let peakNotesPerMinute: Int?

    public init(counts: [String: Int], accuracy: Double, grade: RhythmGrade, strong: [LetterLine],
                weak: [LetterLine], letters: [LetterLine], confusions: [Confusion],
                fingerMissRate: [String: Double], fingerCounts: [String: [String: Int]]? = nil, maxMissStreak: Int,
                survivedSeconds: Double? = nil, peakNotesPerMinute: Int? = nil) {
        self.counts = counts
        self.accuracy = accuracy
        self.grade = grade
        self.strong = strong
        self.weak = weak
        self.letters = letters
        self.confusions = confusions
        self.fingerMissRate = fingerMissRate
        self.fingerCounts = fingerCounts
        self.maxMissStreak = maxMissStreak
        self.survivedSeconds = survivedSeconds
        self.peakNotesPerMinute = peakNotesPerMinute
    }

    public static func make(game: RhythmGame, chart: RhythmChart) -> RhythmReport {
        var counts = ["perfect": 0, "good": 0, "early": 0, "late": 0, "wrongKey": 0, "skipped": 0]
        var letterStats: [Character: (notes: Int, hits: Int, offsetSum: Double, offsetCount: Int)] = [:]
        var confusionCounts: [[String]: Int] = [:]
        var laneStats: [Int: (notes: Int, misses: Int)] = [:]
        var laneCounts: [Int: [String: Int]] = [:]
        var evaluated = 0, hits = 0, misses = 0
        var streak = 0, maxStreak = 0
        var lastEvaluated: RhythmNote?

        for note in chart.notes {
            guard let outcome = game.outcomes[note.index] else { continue }
            evaluated += 1
            lastEvaluated = note
            let key: String
            switch outcome {
            case .perfect: key = "perfect"
            case .good: key = "good"
            case .early: key = "early"
            case .late: key = "late"
            case .miss(.skipped): key = "skipped"
            case .miss(.wrongKey(let pressed)):
                key = "wrongKey"
                confusionCounts[[String(note.character), String(pressed)], default: 0] += 1
            }
            counts[key, default: 0] += 1
            if outcome.isHit {
                hits += 1
                streak = 0
            } else {
                misses += 1
                streak += 1
                maxStreak = max(maxStreak, streak)
            }
            if case .finger(let lane) = note.lane {
                var stat = laneStats[lane] ?? (0, 0)
                stat.notes += 1
                if !outcome.isHit { stat.misses += 1 }
                laneStats[lane] = stat
                laneCounts[lane, default: [:]][key, default: 0] += 1
            }
            if note.lane != .space, note.character != " " {
                var stat = letterStats[note.character] ?? (0, 0, 0, 0)
                stat.notes += 1
                if outcome.isHit { stat.hits += 1 }
                if let offset = game.offsets[note.index] {
                    stat.offsetSum += offset * 1000
                    stat.offsetCount += 1
                }
                letterStats[note.character] = stat
            }
        }

        let accuracy = evaluated == 0 ? 0 : Double(hits) / Double(evaluated)
        let grade = grade(state: game.state, evaluated: evaluated, hits: hits, misses: misses,
                          perfects: counts["perfect"] ?? 0)

        let letters = letterStats.map { character, stat in
            LetterLine(character: String(character), notes: stat.notes,
                       accuracy: Double(stat.hits) / Double(stat.notes),
                       meanOffsetMs: stat.offsetCount == 0 ? 0 : stat.offsetSum / Double(stat.offsetCount))
        }.sorted { $0.character < $1.character }

        let rated = letters.filter { $0.notes >= minLetterNotes }
        let strong = rated.sorted { lhs, rhs in
            if lhs.accuracy != rhs.accuracy { return lhs.accuracy > rhs.accuracy }
            if !nearlyEqual(lhs.meanOffsetMs, rhs.meanOffsetMs) { return abs(lhs.meanOffsetMs) < abs(rhs.meanOffsetMs) }
            return lhs.character < rhs.character
        }.prefix(topLetters)
        // Слабая — только с промахами или заметным сдвигом, и не из сильных: чистый заход слабых не имеет.
        let strongCharacters = Set(strong.map(\.character))
        let weak = rated.filter { line in
            !strongCharacters.contains(line.character)
                && (line.accuracy < 1 || abs(line.meanOffsetMs) >= weakOffsetMs - 1e-6)
        }.sorted { lhs, rhs in
            if lhs.accuracy != rhs.accuracy { return lhs.accuracy < rhs.accuracy }
            if !nearlyEqual(lhs.meanOffsetMs, rhs.meanOffsetMs) { return abs(lhs.meanOffsetMs) > abs(rhs.meanOffsetMs) }
            return lhs.character < rhs.character
        }.prefix(topLetters)

        let confusions = confusionCounts.map { pair, count in
            Confusion(expected: pair[0], pressed: pair[1], count: count)
        }.sorted { lhs, rhs in
            if lhs.count != rhs.count { return lhs.count > rhs.count }
            if lhs.expected != rhs.expected { return lhs.expected < rhs.expected }
            return lhs.pressed < rhs.pressed
        }.prefix(topConfusions)

        var fingerMissRate: [String: Double] = [:]
        for (lane, stat) in laneStats where RhythmLane.fingerOrder.indices.contains(lane) {
            fingerMissRate[RhythmLane.fingerOrder[lane].rawValue] = Double(stat.misses) / Double(stat.notes)
        }
        var fingerCounts: [String: [String: Int]] = [:]
        for (lane, lineCounts) in laneCounts where RhythmLane.fingerOrder.indices.contains(lane) {
            fingerCounts[RhythmLane.fingerOrder[lane].rawValue] = lineCounts
        }

        // Бесконечный режим: сколько продержались и на каком темпе. Ничего не оценено — 0 с на стартовом темпе.
        var survived: Double?
        var peak: Int?
        if chart.level.id == .endless {
            survived = lastEvaluated.map { $0.time - (chart.notes.first?.time ?? $0.time) } ?? 0
            peak = lastEvaluated.map { RhythmEndless.notesPerMinute(noteIndex: $0.index) }
                ?? RhythmEndless.startNotesPerMinute
        }

        return RhythmReport(counts: counts, accuracy: accuracy, grade: grade, strong: Array(strong),
                            weak: Array(weak), letters: letters, confusions: Array(confusions),
                            fingerMissRate: fingerMissRate, fingerCounts: fingerCounts, maxMissStreak: maxStreak,
                            survivedSeconds: survived, peakNotesPerMinute: peak)
    }

    /// Сдвиги в мс равны с точностью до шума `Double` (сравниваются модули).
    private static func nearlyEqual(_ lhs: Double, _ rhs: Double) -> Bool {
        abs(abs(lhs) - abs(rhs)) < 1e-6
    }

    /// Целочисленные сравнения — без ошибок округления на границах.
    private static func grade(state: RhythmGame.State, evaluated: Int, hits: Int, misses: Int,
                              perfects: Int) -> RhythmGrade {
        // Оценка буквой — только у пройденного трека: проваленный и незавершённый заход — D.
        guard evaluated > 0, state == .cleared else { return .d }
        if misses == 0, perfects * 100 >= 90 * evaluated { return .s }
        if hits * 100 >= 95 * evaluated { return .a }
        if hits * 100 >= 90 * evaluated { return .b }
        if hits * 100 >= 80 * evaluated { return .c }
        return .d
    }
}
