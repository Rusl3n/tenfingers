import Foundation

public enum RhythmLevelID: String, CaseIterable, Sendable {
    case easy, medium, hard, expert, personal, endless
}

/// Темп игры: BPM, нот на долю и скорость прокрутки (сколько секунд нота едет до линии).
public struct RhythmLevel: Equatable, Sendable {
    public let id: RhythmLevelID
    public let bpm: Int
    public let notesPerBeat: Int
    public let scrollSeconds: Double

    public init(id: RhythmLevelID, bpm: Int, notesPerBeat: Int, scrollSeconds: Double) {
        self.id = id
        self.bpm = bpm
        self.notesPerBeat = notesPerBeat
        self.scrollSeconds = scrollSeconds
    }

    /// Интервал между нотами: каждая доля (и её часть) занята нотой.
    public var noteInterval: TimeInterval { 60 / Double(bpm) / Double(notesPerBeat) }

    /// Готовые уровни. Для `.personal` — как «Лёгкий» (нет скорости печати).
    public static func preset(_ id: RhythmLevelID) -> RhythmLevel {
        switch id {
        case .easy: RhythmLevel(id: .easy, bpm: 45, notesPerBeat: 1, scrollSeconds: 3.5)
        case .medium: RhythmLevel(id: .medium, bpm: 60, notesPerBeat: 1, scrollSeconds: 3.0)
        case .hard: RhythmLevel(id: .hard, bpm: 80, notesPerBeat: 1, scrollSeconds: 2.6)
        case .expert: RhythmLevel(id: .expert, bpm: 100, notesPerBeat: 1, scrollSeconds: 2.2)
        case .personal: RhythmLevel(id: .personal, bpm: 45, notesPerBeat: 1, scrollSeconds: 3.5)
        // Бесконечный: стартовые значения (темп растёт ступенями, см. `RhythmEndless`).
        case .endless: RhythmLevel(id: .endless, bpm: 40, notesPerBeat: 1, scrollSeconds: 3.6)
        }
    }

    /// «Под меня»: нот в минуту = 0,3 × скорость печати (знаков в минуту): читать падающие буквы под бит труднее,
    /// чем печатать текст. Плотность 1, BPM ограничен 45…120. Нет скорости — как «Лёгкий».
    public static func personal(cpm: Double?) -> RhythmLevel {
        guard let cpm, cpm.isFinite, cpm > 0 else {
            let easy = preset(.easy)
            return RhythmLevel(id: .personal, bpm: easy.bpm, notesPerBeat: easy.notesPerBeat,
                               scrollSeconds: easy.scrollSeconds)
        }
        let bpm = Int(min(120, max(45, 0.3 * cpm)).rounded())
        return RhythmLevel(id: .personal, bpm: bpm, notesPerBeat: 1, scrollSeconds: 2.6)
    }
}
