import Foundation
import SwiftData
import Testing
import TypingCore
@testable import TenFingers

private let msk = TimeZone(identifier: "Europe/Moscow")!
private let now = Date(timeIntervalSince1970: 1_800_000_000)

private func counts(perfect: Int = 0, good: Int = 0, early: Int = 0, late: Int = 0, wrongKey: Int = 0,
                    skipped: Int = 0) -> Data {
    let value = ["perfect": perfect, "good": good, "early": early, "late": late, "wrongKey": wrongKey,
                 "skipped": skipped]
    return try! JSONEncoder().encode(value)
}

@MainActor private func addTrack(_ context: ModelContext, mode: String = "open", level: String = "easy",
                                 endedAt: Date, cleared: Bool = true, grade: String = "B", combo: Int = 30,
                                 judgements: Data, seconds: Double = 60, report: Data = Data("{}".utf8)) {
    context.insert(RhythmResult(language: "ru", mode: mode, level: level, bpm: 90, startedAt: endedAt.addingTimeInterval(-seconds),
                                endedAt: endedAt, score: 1000, accuracy: 0.9, maxCombo: combo, grade: grade,
                                cleared: cleared, judgements: judgements, report: report))
    context.insert(SessionRecord(
        mode: "rhythm", language: "ru", lessonId: nil, startedAt: endedAt.addingTimeInterval(-seconds), endedAt: endedAt,
        logicalDay: "2027-01-15", activeSeconds: seconds, chars: 50, errorCount: 0, cpm: 0, accuracy: 0.9,
        completed: cleared, hintLevel: "full", maxErrorStreak: 0, wrongKeystrokes: 0, exerciseKind: nil,
        source: "rhythm:\(mode)", textTraits: 0))
}

@MainActor private func service(_ context: ModelContext) -> AchievementService {
    AchievementService(recorder: ResultRecorder(context: context, dayStartHour: 4), goalSeconds: { 600 },
                       timeZone: msk, now: { now }, catalog: AchievementCatalog.all)
}

@MainActor private func rhythmDates(_ context: ModelContext) throws -> [String: Date] {
    let records = try context.fetch(FetchDescriptor<AchievementRecord>())
    return Dictionary(uniqueKeysWithValues: records.filter { $0.achievementId.hasPrefix("rhythm.") }
        .map { ($0.achievementId, $0.unlockedAt) })
}

@MainActor @Test func factsComeFromTheStoredResultsJudgements() throws {
    let container = try ModelStore.makeContainer(inMemory: true)
    let context = container.mainContext
    let day = now.addingTimeInterval(-86_400)
    addTrack(context, endedAt: day, judgements: counts(perfect: 40))
    addTrack(context, mode: "words", level: "expert", endedAt: day.addingTimeInterval(100), grade: "A",
             judgements: counts(perfect: 30, good: 5, wrongKey: 1, skipped: 2))
    addTrack(context, mode: "closed", endedAt: day.addingTimeInterval(200), cleared: false, grade: "D",
             judgements: counts(perfect: 3, skipped: 4))
    try context.save()
    let facts = try service(context).facts().rhythm.sorted { $0.endedAt < $1.endedAt }
    #expect(facts.count == 3)
    #expect(facts[0] == RhythmFact(endedAt: day, mode: .open, level: .easy, cleared: true, grade: .b, maxCombo: 30,
                                   misses: 0, allPerfect: true))
    #expect(facts[1].misses == 3 && !facts[1].allPerfect && facts[1].mode == .words && facts[1].level == .expert
            && facts[1].grade == .a)
    #expect(facts[2].misses == 4 && !facts[2].cleared && !facts[2].allPerfect)
}

@MainActor @Test func unreadableJudgementsFallBackToTheReportAndThenToAccuracy() throws {
    let report = RhythmReport(counts: ["perfect": 9, "good": 0, "early": 0, "late": 0, "wrongKey": 1, "skipped": 0],
                              accuracy: 0.9, grade: .b, strong: [], weak: [], letters: [], confusions: [],
                              fingerMissRate: [:], maxMissStreak: 1)
    let withReport = RhythmResult(language: "ru", mode: "open", level: "easy", bpm: 90, startedAt: now, endedAt: now,
                                  score: 1, accuracy: 0.9, maxCombo: 5, grade: "B", cleared: true,
                                  judgements: Data("не json".utf8), report: try JSONEncoder().encode(report))
    #expect(AchievementService.rhythmFact(withReport)?.misses == 1)
    let blind = RhythmResult(language: "ru", mode: "open", level: "easy", bpm: 90, startedAt: now, endedAt: now,
                             score: 1, accuracy: 0.9, maxCombo: 5, grade: "B", cleared: true,
                             judgements: Data(), report: Data())
    let fact = AchievementService.rhythmFact(blind)
    #expect(fact?.misses == 1 && fact?.allPerfect == false)
    let unknown = RhythmResult(language: "ru", mode: "future", level: "easy", bpm: 90, startedAt: now, endedAt: now,
                               score: 1, accuracy: 1, maxCombo: 5, grade: "B", cleared: true,
                               judgements: Data(), report: Data())
    #expect(AchievementService.rhythmFact(unknown) == nil)
}

@MainActor @Test func emptyJudgementsFallBackToTheReportAndNeverGiveFullComboBlind() throws {
    func result(accuracy: Double, judgements: Data, report: Data) -> RhythmResult {
        RhythmResult(language: "ru", mode: "open", level: "easy", bpm: 90, startedAt: now, endedAt: now, score: 1,
                     accuracy: accuracy, maxCombo: 5, grade: "B", cleared: true, judgements: judgements, report: report)
    }
    let report = RhythmReport(counts: ["perfect": 9, "good": 0, "early": 0, "late": 0, "wrongKey": 0, "skipped": 1],
                              accuracy: 0.9, grade: .b, strong: [], weak: [], letters: [], confusions: [],
                              fingerMissRate: [:], maxMissStreak: 1)
    // «{}» из архива без ключа: оценки берутся из разбора.
    let fromReport = AchievementService.rhythmFact(
        result(accuracy: 1, judgements: Data("{}".utf8), report: try JSONEncoder().encode(report)))
    #expect(fromReport?.misses == 1 && fromReport?.allPerfect == false)
    // Ни оценок, ни разбора (и «{}» тоже): ни полного комбо, ни «все точно», даже при точности 100%.
    let blind = AchievementService.rhythmFact(
        result(accuracy: 1, judgements: Data("{}".utf8), report: Data("{}".utf8)))
    #expect((blind?.misses ?? 0) > 0 && blind?.allPerfect == false)
}

@MainActor @Test func serviceGrantsRhythmAchievementsWithTheDateOfTheDecidingResult() throws {
    let container = try ModelStore.makeContainer(inMemory: true)
    let context = container.mainContext
    let base = now.addingTimeInterval(-10 * 86_400)
    // Проигранный трек: ни одной ачивки, но время идёт в `rhythm.hour`.
    addTrack(context, endedAt: base, cleared: false, grade: "D", combo: 500, judgements: counts(perfect: 5, skipped: 9),
             seconds: 1800)
    addTrack(context, mode: "open", endedAt: base.addingTimeInterval(1000), grade: "A", judgements: counts(perfect: 20, good: 2, late: 1, skipped: 1),
             seconds: 600)
    addTrack(context, mode: "closed", endedAt: base.addingTimeInterval(2000), grade: "S", combo: 120,
             judgements: counts(perfect: 50), seconds: 700)
    addTrack(context, mode: "problem", level: "expert", endedAt: base.addingTimeInterval(3000), grade: "S",
             judgements: counts(perfect: 45, good: 5), seconds: 600)
    try context.save()

    _ = try service(context).check(reason: .afterSave)
    let dates = try rhythmDates(context)
    #expect(dates["rhythm.first"] == base.addingTimeInterval(1000))
    #expect(dates["rhythm.fullcombo"] == base.addingTimeInterval(2000))
    #expect(dates["rhythm.perfect"] == base.addingTimeInterval(2000))
    #expect(dates["rhythm.combo100"] == base.addingTimeInterval(2000))
    #expect(dates["rhythm.s.expert"] == base.addingTimeInterval(3000))
    #expect(dates["rhythm.allmodes"] == nil)
    // 1800 (проигранный) + 600 + 700 + 600 = 3700: час набрался на последней сессии.
    #expect(dates["rhythm.hour"] == base.addingTimeInterval(3000))
    #expect(dates.count == 6)
}

@MainActor @Test func endlessResultGivesAFactAndOnlyAClearedOneCountsAsATrack() throws {
    let container = try ModelStore.makeContainer(inMemory: true)
    let context = container.mainContext
    let report = RhythmReport(counts: ["perfect": 30, "good": 0, "early": 0, "late": 0, "wrongKey": 0, "skipped": 20],
                              accuracy: 0.6, grade: .d, strong: [], weak: [], letters: [], confusions: [],
                              fingerMissRate: [:], maxMissStreak: 20, survivedSeconds: 90, peakNotesPerMinute: 55)
    addTrack(context, level: "endless", endedAt: now.addingTimeInterval(-3600), cleared: false, grade: "D",
             judgements: counts(perfect: 30, skipped: 20), report: try JSONEncoder().encode(report))
    try context.save()
    let facts = try service(context).facts().rhythm
    #expect(facts.count == 1)
    #expect(facts[0].level == .endless && !facts[0].cleared && facts[0].grade == .d && facts[0].misses == 20)
    #expect(!facts[0].allPerfect)
    // Проигранный заход «пройденным треком» не считается: ачивок за трек нет (время в игре — отдельно).
    _ = try service(context).check(reason: .afterSave)
    #expect(try rhythmDates(context).isEmpty)
}
