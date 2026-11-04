import Foundation

/// Итог захода для записи в базу (решения 8–9): всё, что нужно приложению, без обращения к `RhythmGame`.
/// Считаются только оценённые ноты; «лишние» нажатия (`stray`) — только в `wrongKeystrokes`, в статистику букв не идут.
public struct RhythmOutcome: Sendable {
    public let language: Language
    public let mode: RhythmNoteMode
    public let level: RhythmLevel
    public let startedAt: Date
    public let endedAt: Date
    /// Чистое время захода (без пауз и отсчёта), секунды.
    public let activeSeconds: Double
    /// Трек пройден до конца при здоровье > 0.
    public let cleared: Bool
    /// Заход завершён как обычный: трек пройден, либо бесконечный режим и кончилось здоровье.
    /// Выход до конца (Esc) — не завершён. `cleared` от бесконечного конца по здоровью не меняется.
    public let completed: Bool
    public let score: Int
    public let maxCombo: Int
    public let report: RhythmReport
    /// Исход каждой оценённой ноты буквы по порядку нот; `true` — ошибка (`miss`). Пробел — тоже.
    public let keySamples: [Character: [Bool]]
    /// Нажатия (оценённые ноты) и ошибки (`miss`) по пальцам; пробел — `thumb`.
    public let fingerPresses: [Finger: Int]
    public let fingerErrors: [Finger: Int]
    /// Оценённых нот.
    public let notes: Int
    public let misses: Int
    /// `miss(.wrongKey)` и «лишние» нажатия.
    public let wrongKeystrokes: Int
    public let maxMissStreak: Int
    /// Код физической клавиши каждого символа в текущей раскладке; символа нет — клавиши для него нет.
    public let keyCodes: [Character: UInt16]

    public init(language: Language, mode: RhythmNoteMode, level: RhythmLevel, startedAt: Date, endedAt: Date,
                activeSeconds: Double, cleared: Bool, score: Int, maxCombo: Int, report: RhythmReport,
                keySamples: [Character: [Bool]], fingerPresses: [Finger: Int], fingerErrors: [Finger: Int],
                notes: Int, misses: Int, wrongKeystrokes: Int, maxMissStreak: Int,
                keyCodes: [Character: UInt16] = [:], completed: Bool? = nil) {
        self.language = language
        self.mode = mode
        self.level = level
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.activeSeconds = activeSeconds
        self.cleared = cleared
        self.completed = completed ?? cleared
        self.score = score
        self.maxCombo = maxCombo
        self.report = report
        self.keySamples = keySamples
        self.fingerPresses = fingerPresses
        self.fingerErrors = fingerErrors
        self.notes = notes
        self.misses = misses
        self.wrongKeystrokes = wrongKeystrokes
        self.maxMissStreak = maxMissStreak
        self.keyCodes = keyCodes
    }

    /// Итог по заходу и его расстановке. `fingers` — карта символ → палец раскладки языка; нет в карте — палец дорожки.
    /// `keyCodes` — коды клавиш символов текущей раскладки (нужны для новых строк `KeyStat`).
    public static func make(game: RhythmGame, chart: RhythmChart, source: RhythmNoteSource, language: Language,
                            startedAt: Date, endedAt: Date, activeSeconds: Double,
                            fingers: [Character: Finger], keyCodes: [Character: UInt16] = [:]) -> RhythmOutcome {
        var samples: [Character: [Bool]] = [:]
        var presses: [Finger: Int] = [:]
        var errors: [Finger: Int] = [:]
        var notes = 0, misses = 0, wrongKey = 0
        for note in chart.notes {
            guard let outcome = game.outcomes[note.index] else { continue }
            let isMiss = !outcome.isHit
            notes += 1
            if isMiss { misses += 1 }
            if case .miss(.wrongKey) = outcome { wrongKey += 1 }
            samples[note.character, default: []].append(isMiss)
            if let finger = fingers[note.character] ?? laneFinger(note.lane) {
                presses[finger, default: 0] += 1
                errors[finger, default: 0] += isMiss ? 1 : 0
            }
        }
        let report = RhythmReport.make(game: game, chart: chart)
        return RhythmOutcome(
            language: language, mode: source.mode, level: chart.level, startedAt: startedAt, endedAt: endedAt,
            activeSeconds: activeSeconds, cleared: game.state == .cleared, score: game.score,
            maxCombo: game.maxCombo, report: report, keySamples: samples, fingerPresses: presses,
            fingerErrors: errors, notes: notes, misses: misses, wrongKeystrokes: wrongKey + game.strays,
            maxMissStreak: report.maxMissStreak, keyCodes: keyCodes,
            completed: game.state == .cleared || (chart.level.id == .endless && game.state == .failed))
    }

    private static func laneFinger(_ lane: RhythmLane) -> Finger? {
        switch lane {
        case .space: .thumb
        case .finger(let index): RhythmLane.fingerOrder.indices.contains(index) ? RhythmLane.fingerOrder[index] : nil
        }
    }
}
