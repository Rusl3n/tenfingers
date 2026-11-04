import Foundation
import Testing
import TypingCore
@testable import TenFingers

private func result(language: String = "ru", mode: String = "open", level: String = "easy", score: Int,
                    accuracy: Double = 0.9, combo: Int = 10, grade: String = "B", cleared: Bool = true,
                    endedAt: Date = .now) -> RhythmResult {
    RhythmResult(language: language, mode: mode, level: level, bpm: 80, startedAt: endedAt, endedAt: endedAt, score: score,
                 accuracy: accuracy, maxCombo: combo, grade: grade, cleared: cleared, judgements: Data(), report: Data())
}

private func records(_ results: [RhythmResult], language: Language = .ru, mode: RhythmNoteMode = .open,
                     level: RhythmLevelID = .easy) -> RhythmRecords {
    RhythmRecords.make(results, language: language, mode: mode, level: level)
}

@Test func noResultsMeansNoRecords() {
    let empty = records([])
    #expect(empty == .empty)
}

@Test func failedTrackIsNotARecord() {
    let only = records([result(score: 99999, accuracy: 1, combo: 500, grade: "S", cleared: false)])
    #expect(only.bestScore == nil && only.bestAccuracy == nil && only.bestCombo == nil && only.bestGrade == nil)
    let mixed = records([result(score: 99999, cleared: false), result(score: 500, accuracy: 0.8, combo: 7, grade: "C")])
    #expect(mixed == RhythmRecords(bestScore: 500, bestAccuracy: 0.8, bestCombo: 7, bestGrade: .c))
}

@Test func modeLevelAndLanguageAreNotMixed() {
    let all = [result(score: 100), result(mode: "words", score: 900), result(level: "hard", score: 800),
               result(language: "en", score: 700)]
    #expect(records(all).bestScore == 100)
    #expect(records(all, mode: .words).bestScore == 900)
    #expect(records(all, level: .hard).bestScore == 800)
    #expect(records(all, language: .en).bestScore == 700)
    #expect(records(all, mode: .problem).bestScore == nil)
}

@Test func eachRecordComesFromItsOwnBestRun() {
    let best = records([result(score: 300, accuracy: 0.97, combo: 5, grade: "A"),
                        result(score: 900, accuracy: 0.85, combo: 40, grade: "C"),
                        result(score: 100, accuracy: 0.92, combo: 12, grade: "S")])
    #expect(best == RhythmRecords(bestScore: 900, bestAccuracy: 0.97, bestCombo: 40, bestGrade: .s))
    #expect(records([result(score: 1, grade: "D"), result(score: 2, grade: "B"), result(score: 3, grade: "C")])
        .bestGrade == .b)
    #expect(records([result(score: 1, grade: "A"), result(score: 2, grade: "S"), result(score: 3, grade: "B")])
        .bestGrade == .s)
}

@Test func newBestNeedsStrictlyMoreScore() {
    let previous = records([result(score: 1000)])
    #expect(RhythmRecords.isNewBest(score: 1001, previous: previous))
    #expect(!RhythmRecords.isNewBest(score: 1000, previous: previous))
    #expect(!RhythmRecords.isNewBest(score: 999, previous: previous))
}

@Test func firstClearedRunIsARecord() {
    #expect(RhythmRecords.isNewBest(score: 0, previous: records([])))
    // Проигранный заход прежнего рекорда не создаёт: следующий пройденный — снова первый.
    #expect(RhythmRecords.isNewBest(score: 10, previous: records([result(score: 5000, cleared: false)])))
}

private func latestIsBest(_ results: [RhythmResult], mode: RhythmNoteMode = .open) -> Bool {
    RhythmRecords.latestSetBest(results, language: .ru, mode: mode, level: .easy)
}

@Test func latestClearedRunSetsTheMarkOnlyWhenItBeatsAllEarlierOnes() {
    let t = Date(timeIntervalSince1970: 1_800_000_000)
    #expect(!latestIsBest([]))
    #expect(latestIsBest([result(score: 10, endedAt: t)]))
    #expect(latestIsBest([result(score: 500, endedAt: t), result(score: 900, endedAt: t.addingTimeInterval(60))]))
    // Свежий заход слабее прежнего рекорда (порядок в массиве не важен) или равен ему — отметки нет.
    #expect(!latestIsBest([result(score: 900, endedAt: t.addingTimeInterval(60)), result(score: 500, endedAt: t.addingTimeInterval(120))]))
    #expect(!latestIsBest([result(score: 900, endedAt: t), result(score: 900, endedAt: t.addingTimeInterval(60))]))
}

@Test func failedOrForeignRunsDoNotMoveTheRecordMark() {
    let t = Date(timeIntervalSince1970: 1_800_000_000)
    let results = [result(score: 500, endedAt: t), result(score: 9999, cleared: false, endedAt: t.addingTimeInterval(60)),
                   result(mode: "words", score: 100, endedAt: t.addingTimeInterval(120))]
    #expect(latestIsBest(results))
    #expect(latestIsBest(results, mode: .words))
    #expect(!latestIsBest(results, mode: .problem))
}

// MARK: - Бесконечный режим

private func endless(seconds: Double?, score: Int, language: String = "ru", mode: String = "open", cleared: Bool = false,
                     endedAt: Date = .now) -> RhythmResult {
    let report = seconds.map {
        try! JSONEncoder().encode(RhythmReport(
            counts: [:], accuracy: 0.5, grade: .d, strong: [], weak: [], letters: [], confusions: [],
            fingerMissRate: [:], maxMissStreak: 0, survivedSeconds: $0, peakNotesPerMinute: 60))
    } ?? Data()
    return RhythmResult(language: language, mode: mode, level: "endless", bpm: 40, startedAt: endedAt, endedAt: endedAt,
                        score: score, accuracy: 0.5, maxCombo: 3, grade: "D", cleared: cleared, judgements: Data(),
                        report: report)
}

private func endlessRecords(_ results: [RhythmResult], language: Language = .ru,
                            mode: RhythmNoteMode = .open) -> RhythmEndlessRecords {
    RhythmEndlessRecords.make(results, language: language, mode: mode)
}

@Test func endlessRecordsTakeBestTimeAndScoreFromAllRunsNotOnlyCleared() {
    #expect(endlessRecords([]) == .empty)
    let best = endlessRecords([endless(seconds: 120, score: 900), endless(seconds: 300, score: 400),
                               endless(seconds: 200, score: 700, cleared: true)])
    #expect(best == RhythmEndlessRecords(bestSeconds: 300, bestScore: 900))
}

@Test func endlessRecordsKeepLanguageAndModeApartAndIgnoreOrdinaryLevels() {
    let all = [endless(seconds: 100, score: 100), endless(seconds: 500, score: 500, mode: "words"),
               endless(seconds: 700, score: 700, language: "en"), result(score: 9999)]
    #expect(endlessRecords(all) == RhythmEndlessRecords(bestSeconds: 100, bestScore: 100))
    #expect(endlessRecords(all, mode: .words).bestSeconds == 500)
    #expect(endlessRecords(all, language: .en).bestSeconds == 700)
    #expect(endlessRecords(all, mode: .problem) == .empty)
}

@Test func endlessRunWithoutReadableReportCountsOnlyInScore() {
    let records = endlessRecords([endless(seconds: nil, score: 800), endless(seconds: 60, score: 100)])
    #expect(records == RhythmEndlessRecords(bestSeconds: 60, bestScore: 800))
    #expect(endlessRecords([endless(seconds: nil, score: 5)]) == RhythmEndlessRecords(bestSeconds: nil, bestScore: 5))
}

@Test func newEndlessBestNeedsStrictlyMoreTime() {
    let previous = endlessRecords([endless(seconds: 200, score: 1)])
    #expect(RhythmEndlessRecords.isNewBest(seconds: 200.5, previous: previous))
    #expect(!RhythmEndlessRecords.isNewBest(seconds: 200, previous: previous))
    #expect(!RhythmEndlessRecords.isNewBest(seconds: 10, previous: previous))
    #expect(RhythmEndlessRecords.isNewBest(seconds: 0, previous: .empty))
}

@Test func ordinaryRecordsIgnoreEndlessRunsEvenClearedOnes() {
    let all = [endless(seconds: 1200, score: 99999, cleared: true), result(score: 100)]
    #expect(records(all) == RhythmRecords(bestScore: 100, bestAccuracy: 0.9, bestCombo: 10, bestGrade: .b))
    #expect(records(all, level: .endless) == .empty)
    #expect(!RhythmRecords.latestSetBest(all, language: .ru, mode: .open, level: .endless))
}
