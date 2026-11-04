import Foundation
import TypingCore

/// Рекорды сочетания режим + уровень + язык. Считаются только по пройденным (`cleared`) заходам: проигранный
/// с большими очками рекордом не становится. Нет пройденных — все поля `nil`.
struct RhythmRecords: Equatable {
    let bestScore: Int?
    let bestAccuracy: Double?
    let bestCombo: Int?
    let bestGrade: RhythmGrade?

    /// Ни одного пройденного захода.
    static let empty = RhythmRecords(bestScore: nil, bestAccuracy: nil, bestCombo: nil, bestGrade: nil)

    /// Порядок букв от худшей к лучшей: S > A > B > C > D.
    private static let gradeOrder: [RhythmGrade] = [.d, .c, .b, .a, .s]

    /// Лучшее по каждому показателю среди пройденных заходов сочетания (других записей не касается).
    /// У бесконечного уровня своих «пройденных» рекордов нет: его заходы — в `RhythmEndlessRecords`.
    static func make(_ results: [RhythmResult], language: Language, mode: RhythmNoteMode,
                     level: RhythmLevelID) -> RhythmRecords {
        guard level != .endless else { return .empty }
        let cleared = results.filter {
            $0.cleared && $0.language == language.rawValue && $0.mode == mode.rawValue && $0.level == level.rawValue
        }
        guard !cleared.isEmpty else { return .empty }
        let grades = cleared.compactMap { RhythmGrade(rawValue: $0.grade) }
        return RhythmRecords(
            bestScore: cleared.map(\.score).max(), bestAccuracy: cleared.map(\.accuracy).max(),
            bestCombo: cleared.map(\.maxCombo).max(),
            bestGrade: grades.max { (gradeOrder.firstIndex(of: $0) ?? 0) < (gradeOrder.firstIndex(of: $1) ?? 0) })
    }

    /// Последний пройденный заход сочетания поставил рекорд очков: его очки строго больше очков всех прежних
    /// пройденных (первый пройденный — рекорд). Нет пройденных — `false`.
    static func latestSetBest(_ results: [RhythmResult], language: Language, mode: RhythmNoteMode,
                              level: RhythmLevelID) -> Bool {
        guard level != .endless else { return false }
        let cleared = results.filter {
            $0.cleared && $0.language == language.rawValue && $0.mode == mode.rawValue && $0.level == level.rawValue
        }.sorted { $0.endedAt < $1.endedAt }
        guard let latest = cleared.last else { return false }
        return cleared.dropLast().allSatisfy { latest.score > $0.score }
    }

    /// Очки строго больше прежнего рекорда; прежнего нет (первый пройденный) — рекорд. Что заход пройден,
    /// проверяет вызывающий.
    static func isNewBest(score: Int, previous: RhythmRecords) -> Bool {
        guard let best = previous.bestScore else { return true }
        return score > best
    }
}

/// Рекорды бесконечного режима по набору нот и языку: лучшее время и лучшие очки — по всем заходам `endless`,
/// не только пройденным (заход кончается здоровьем). Время — `RhythmReport.survivedSeconds`; запись без
/// читаемого разбора или без этого поля (до его появления) во времени не участвует, в очках — участвует.
struct RhythmEndlessRecords: Equatable {
    let bestSeconds: Double?
    let bestScore: Int?

    /// Заходов бесконечного режима ещё не было.
    static let empty = RhythmEndlessRecords(bestSeconds: nil, bestScore: nil)

    static func make(_ results: [RhythmResult], language: Language, mode: RhythmNoteMode) -> RhythmEndlessRecords {
        let own = results.filter {
            $0.level == RhythmLevelID.endless.rawValue && $0.language == language.rawValue && $0.mode == mode.rawValue
        }
        guard !own.isEmpty else { return .empty }
        let decoder = JSONDecoder()
        let seconds = own.compactMap { (try? decoder.decode(RhythmReport.self, from: $0.report))?.survivedSeconds }
        return RhythmEndlessRecords(bestSeconds: seconds.max(), bestScore: own.map(\.score).max())
    }

    /// Продержались строго дольше прежнего лучшего; прежнего времени нет (первый заход) — рекорд.
    static func isNewBest(seconds: Double, previous: RhythmEndlessRecords) -> Bool {
        guard let best = previous.bestSeconds else { return true }
        return seconds > best
    }
}
