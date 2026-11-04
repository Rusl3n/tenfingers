import Foundation

public struct RhythmEvent: Equatable, Sendable {
    public let noteIndex: Int?
    public let judgement: RhythmJudgement?
    /// Нажатие − нота; `nil` у пропуска, «лишнего» нажатия и игнорируемых событий.
    public let offset: TimeInterval?
    public let time: TimeInterval
    public let isStray: Bool

    public init(noteIndex: Int?, judgement: RhythmJudgement?, offset: TimeInterval?,
                time: TimeInterval, isStray: Bool) {
        self.noteIndex = noteIndex
        self.judgement = judgement
        self.offset = offset
        self.time = time
        self.isStray = isStray
    }
}

/// Заход: сопоставление нажатий с нотами, комбо, очки и здоровье (§3.4–3.5).
public struct RhythmGame: Sendable {
    public enum State: Sendable { case playing, cleared, failed }

    public static let startHealth = 100
    public static let missPenalty = 5

    public let chart: RhythmChart
    public private(set) var state: State = .playing
    public private(set) var health: Int = RhythmGame.startHealth
    public private(set) var combo = 0
    public private(set) var maxCombo = 0
    public private(set) var score = 0
    public private(set) var outcomes: [Int: RhythmJudgement] = [:]
    public private(set) var offsets: [Int: TimeInterval] = [:]
    public private(set) var strays = 0
    /// Первая нота, которая могла остаться неоценённой.
    private var cursor = 0

    public init(chart: RhythmChart) {
        self.chart = chart
    }

    /// Текущий множитель по текущему комбо.
    public var multiplier: Int {
        switch combo {
        case 30...: 4
        case 20...: 3
        case 10...: 2
        default: 1
        }
    }

    public mutating func press(_ character: Character, at time: TimeInterval) -> RhythmEvent {
        guard state == .playing else {
            return RhythmEvent(noteIndex: nil, judgement: nil, offset: nil, time: time, isStray: false)
        }
        advanceCursor()
        let notes = chart.notes
        var best: Int?
        var bestDistance = TimeInterval.infinity
        var i = cursor
        // Окно ноты не шире обычного (`windowScale ≤ 1`), поэтому обычное окно — верхняя граница поиска.
        while i < notes.count, notes[i].time <= time + RhythmJudge.hitWindow + RhythmJudge.epsilon {
            if outcomes[i] == nil {
                let distance = abs(time - notes[i].time)
                if distance <= RhythmJudge.hitWindow * notes[i].windowScale + RhythmJudge.epsilon,
                   distance < bestDistance - RhythmJudge.epsilon {
                    best = i
                    bestDistance = distance
                }
            }
            i += 1
        }
        guard let index = best else {
            strays += 1
            combo = 0
            return RhythmEvent(noteIndex: nil, judgement: nil, offset: nil, time: time, isStray: true)
        }
        let note = notes[index]
        let offset = time - note.time
        let matches = note.lane == .space ? character == " " : character == note.character
        let judgement: RhythmJudgement
        if matches, let timed = RhythmJudge.timing(offset: offset, scale: note.windowScale) {
            judgement = timed
        } else {
            judgement = .miss(.wrongKey(pressed: character))
        }
        offsets[index] = offset
        record(judgement, at: index)
        return RhythmEvent(noteIndex: index, judgement: judgement, offset: offset, time: time, isStray: false)
    }

    /// Пропуски: каждая неоценённая нота старше своего окна (`windowScale` × 200 мс). События — только для новых пропусков.
    public mutating func tick(at time: TimeInterval) -> [RhythmEvent] {
        guard state == .playing else { return [] }
        var events: [RhythmEvent] = []
        advanceCursor()
        var i = cursor
        while i < chart.notes.count, state == .playing,
              time - chart.notes[i].time > RhythmJudge.hitWindow * chart.notes[i].windowScale + RhythmJudge.epsilon {
            if outcomes[i] == nil {
                let judgement = RhythmJudgement.miss(.skipped)
                record(judgement, at: i)
                events.append(RhythmEvent(noteIndex: i, judgement: judgement, offset: nil, time: time, isStray: false))
            }
            i += 1
        }
        return events
    }

    private mutating func advanceCursor() {
        while cursor < chart.notes.count, outcomes[cursor] != nil { cursor += 1 }
    }

    private mutating func record(_ judgement: RhythmJudgement, at index: Int) {
        outcomes[index] = judgement
        if judgement.isHit {
            combo += 1
            maxCombo = max(maxCombo, combo)
            score += judgement.points * multiplier
            switch judgement {
            case .perfect: health = min(RhythmGame.startHealth, health + 2)
            case .good: health = min(RhythmGame.startHealth, health + 1)
            default: break
            }
        } else {
            combo = 0
            health -= RhythmGame.missPenalty
        }
        if health <= 0 {
            state = .failed
        } else if outcomes.count == chart.notes.count {
            state = .cleared
        }
    }
}
