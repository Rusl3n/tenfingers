import Foundation
import Testing
@testable import TypingCore

private let zone = TimeZone(identifier: "Europe/Moscow")!
private let now = date("2027-06-01 10:00")

private func date(_ text: String) -> Date {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = zone
    formatter.dateFormat = "yyyy-MM-dd HH:mm"
    return formatter.date(from: text)!
}

private func track(_ time: String, mode: RhythmNoteMode = .open, level: RhythmLevelID = .easy, cleared: Bool = true,
                   grade: RhythmGrade = .b, combo: Int = 20, misses: Int = 3, allPerfect: Bool = false) -> RhythmFact {
    RhythmFact(endedAt: date(time), mode: mode, level: level, cleared: cleared, grade: grade, maxCombo: combo,
               misses: misses, allPerfect: allPerfect)
}

private func session(_ time: String, seconds: Double, mode: ExerciseMode = .rhythm, completed: Bool = true) -> ExerciseFact {
    ExerciseFact(endedAt: date(time), logicalDay: "2026-11-04", language: .ru, mode: mode, chars: 50,
                 activeSeconds: seconds, accuracy: 0.9, cpm: 0, completed: completed)
}

private func earned(_ condition: AchievementCondition, tracks: [RhythmFact] = [],
                    sessions: [ExerciseFact] = []) -> Date? {
    let facts = AchievementFacts(exercises: sessions, rhythm: tracks, timeZone: zone, now: now)
    let probe = Achievement(id: "probe", category: .rhythm, icon: "music.note", condition: condition)
    return AchievementEngine.evaluate(facts, catalog: [probe]).first?.date
}

private func catalogEntry(_ id: String) throws -> Achievement {
    try #require(AchievementCatalog.all.first { $0.id == id })
}

@Test func firstClearedTrackGivesItsDateAndLostOnesDoNot() {
    let lost = track("2026-11-01 10:00", cleared: false, grade: .d, combo: 500, misses: 0, allPerfect: true)
    let won = track("2026-11-02 10:00")
    #expect(earned(.rhythmCleared, tracks: [lost]) == nil)
    #expect(earned(.rhythmCleared, tracks: [lost, won, track("2026-11-03 10:00")]) == date("2026-11-02 10:00"))
    #expect(earned(.rhythmCleared) == nil)
}

@Test func fullComboNeedsAClearedTrackWithoutMisses() {
    let lost = track("2026-11-01 10:00", cleared: false, misses: 0)
    let withMiss = track("2026-11-02 10:00", misses: 1)
    let clean = track("2026-11-03 10:00", misses: 0)
    #expect(earned(.rhythmFullCombo, tracks: [lost, withMiss]) == nil)
    #expect(earned(.rhythmFullCombo, tracks: [lost, withMiss, clean]) == date("2026-11-03 10:00"))
}

@Test func allPerfectNeedsAClearedTrack() {
    let lost = track("2026-11-01 10:00", cleared: false, misses: 0, allPerfect: true)
    let almost = track("2026-11-02 10:00", misses: 0)
    let perfect = track("2026-11-04 10:00", grade: .s, misses: 0, allPerfect: true)
    #expect(earned(.rhythmAllPerfect, tracks: [lost, almost]) == nil)
    #expect(earned(.rhythmAllPerfect, tracks: [lost, almost, perfect]) == date("2026-11-04 10:00"))
}

@Test func comboThresholdIsInclusiveAndNeedsAClearedTrack() {
    let lost = track("2026-11-01 10:00", cleared: false, combo: 300)
    let short = track("2026-11-02 10:00", combo: 99)
    let exact = track("2026-11-03 10:00", combo: 100)
    #expect(earned(.rhythmCombo(100), tracks: [lost, short]) == nil)
    #expect(earned(.rhythmCombo(100), tracks: [lost, short, exact, track("2026-11-04 10:00", combo: 400)])
            == date("2026-11-03 10:00"))
}

@Test func gradeNeedsTheExactLevelAndGrade() {
    let wrongLevel = track("2026-11-01 10:00", level: .hard, grade: .s)
    let wrongGrade = track("2026-11-02 10:00", level: .expert, grade: .a)
    let lost = track("2026-11-03 10:00", level: .expert, cleared: false, grade: .s)
    let right = track("2026-11-04 10:00", level: .expert, grade: .s)
    #expect(earned(.rhythmGrade(.s, level: .expert), tracks: [wrongLevel, wrongGrade, lost]) == nil)
    #expect(earned(.rhythmGrade(.s, level: .expert), tracks: [wrongLevel, wrongGrade, lost, right])
            == date("2026-11-04 10:00"))
}

@Test func allModesIsDatedByTheFourthModeAndLostTracksDoNotCount() {
    let tracks = [track("2026-11-01 10:00", mode: .open), track("2026-11-02 10:00", mode: .closed),
                  track("2026-11-03 10:00", mode: .problem, cleared: false),
                  track("2026-11-04 10:00", mode: .words)]
    #expect(earned(.rhythmAllModes, tracks: tracks) == nil)
    #expect(earned(.rhythmAllModes, tracks: tracks + [track("2026-11-05 10:00", mode: .problem),
                                                      track("2026-11-06 10:00", mode: .open)])
            == date("2026-11-05 10:00"))
    // Дата — первого пройденного трека четвёртого режима, а не более поздние заходы.
    #expect(earned(.rhythmAllModes, tracks: [track("2026-11-01 10:00", mode: .words),
                                             track("2026-11-02 10:00", mode: .open),
                                             track("2026-11-03 10:00", mode: .closed),
                                             track("2026-11-04 10:00", mode: .problem),
                                             track("2026-11-09 10:00", mode: .problem)]) == date("2026-11-04 10:00"))
}

@Test func rhythmTimeSumsAllRhythmSessionsLostOnesToo() {
    let sessions = [session("2026-11-01 10:00", seconds: 1800), session("2026-11-02 10:00", seconds: 1200, completed: false),
                    session("2026-11-03 10:00", seconds: 600, mode: .practice),
                    session("2026-11-04 10:00", seconds: 599)]
    #expect(earned(.rhythmSeconds(3600), sessions: sessions) == nil)
    let enough = sessions + [session("2026-11-05 10:00", seconds: 1), session("2026-11-06 10:00", seconds: 100)]
    #expect(earned(.rhythmSeconds(3600), sessions: enough) == date("2026-11-05 10:00"))
}

@Test func catalogHasTheSevenRhythmAchievementsInTheirOwnCategory() throws {
    let planned: [(id: String, icon: String, condition: AchievementCondition)] = [
        ("rhythm.first", "music.note", .rhythmCleared),
        ("rhythm.fullcombo", "flame.fill", .rhythmFullCombo),
        ("rhythm.perfect", "star.circle.fill", .rhythmAllPerfect),
        ("rhythm.combo100", "bolt.fill", .rhythmCombo(100)),
        ("rhythm.s.expert", "crown.fill", .rhythmGrade(.s, level: .expert)),
        ("rhythm.allmodes", "square.grid.2x2.fill", .rhythmAllModes),
        ("rhythm.hour", "clock.fill", .rhythmSeconds(3600)),
    ]
    #expect(AchievementCatalog.all.filter { $0.category == .rhythm }.map(\.id) == planned.map(\.id))
    for item in planned {
        let achievement = try catalogEntry(item.id)
        #expect(achievement.icon == item.icon && achievement.condition == item.condition, "«\(item.id)»")
        #expect(!achievement.repeatable && !achievement.secret && !achievement.adult, "«\(item.id)»")
    }
}

@Test func rhythmConditionTextsExistInBothLanguagesWithoutOtherProducts() {
    let conditions: [AchievementCondition] = [
        .rhythmCleared, .rhythmFullCombo, .rhythmAllPerfect, .rhythmCombo(100),
        .rhythmGrade(.s, level: .expert), .rhythmAllModes, .rhythmSeconds(3600),
    ]
    for condition in conditions {
        for localization in ["ru", "en"] {
            let text = AchievementConditionText.describe(condition, localization: localization)
            #expect(!text.isEmpty && !text.contains("achievement.") && !text.contains("%"), "\(condition) \(localization)")
        }
        #expect(AchievementConditionText.describe(condition, localization: "en").unicodeScalars
            .allSatisfy { !(0x400...0x4FF).contains($0.value) }, "английский текст без кириллицы: \(condition)")
    }
    #expect(AchievementConditionText.describe(.rhythmCombo(100), localization: "en").contains("100"))
    #expect(AchievementConditionText.describe(.rhythmSeconds(3600), localization: "ru").contains("60"))
    #expect(AchievementConditionText.describe(.rhythmGrade(.s, level: .expert), localization: "ru").contains("S"))
}
